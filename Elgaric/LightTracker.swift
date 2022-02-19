//
//  LightTracker.swift
//  Elgaric
//
//  Created by Dj Walker-Morgan on 06/02/2022.
//

import Foundation
import Network
import SwiftUI


class LightTracker: ObservableObject {
    
    @Published var lights:[RestLight]=[]
    
    init() {
    }
    
    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        print("In Start")
        let browser = NWBrowser(for: .bonjour(type: "_elg._tcp.", domain: nil), using: parameters)
        browser.stateUpdateHandler = { newState in
        }
        browser.browseResultsChangedHandler = { results, changes in
            print("Results")
            for result in results {
                if case NWEndpoint.service = result.endpoint {
                    let light=RestLight(endpoint: result.endpoint)
                    while(light.ipv4host=="") {
                        print("Sleepy")
                        sleep(1)
                    }
                    
                    if(!self.lights.contains(light)) {
                        DispatchQueue.main.async {
                            self.lights.append(light)
                        }
                    } else {
                        print("Dropped \(light)")
                    }
                    //let ai=light.fetchInfo()
                    //print("Oh \(ai!)")
                }
            }
        }
        browser.start(queue: DispatchQueue.global())
        sleep(5)
    }
}

struct AccessoryInfo: Codable {
    let productName:String?
    let hardwareBoardType:Int?
    let firmwareBuildNumber:Int?
    let firmwareVersion:String?
    let serialNumber:String?
    let displayName:String?
    let features:[String]?
}

struct LightState: Codable {
    let on: Int
    let brightness: Int
    let temperature: Int
}

struct State: Codable {
    let numberOfLights:Int
    let lights:[LightState]
}

class RestLight:Identifiable,CustomStringConvertible,ObservableObject,Equatable {
    
    static func == (lhs: RestLight, rhs: RestLight) -> Bool {
        return (lhs.endpoint==rhs.endpoint)
    }
    

    let endpoint: NWEndpoint
    let name: String
    let description: String
    var ipv4host: String
    var ipv4port: String
    var productName:String?
    var hardwareBoardType:Int?
    var firmwareBuildNumber:Int?
    var firmwareVersion:String?
    var serialNumber:String?
    var displayName:String?
    var features:[String]?
    
    // We are only going to deal with light 0 in this version
    
    @Published var lighton:Int
    @Published var brightness:Double
    @Published var temperature:Int
    
    
    init(endpoint: NWEndpoint) {
        self.endpoint=endpoint
        self.name=String(String(describing:endpoint).split(separator:".")[0])
        self.description=self.name
        self.ipv4host=""
        self.ipv4port=""
        self.lighton=0
        self.brightness=0
        self.temperature=0
        
        getAddress()
        while(self.ipv4host=="") {
            sleep(1)
        }
        fetchInfo()
        fetchState()
    }
    
    
    
    func getAddress() {
        let params = NWParameters.tcp
        let stack = params.defaultProtocolStack.internetProtocol! as! NWProtocolIP.Options
        stack.version = .v4
        let connection = NWConnection(to: endpoint, using: params)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let ipv4hostparts=String(describing:host).components(separatedBy:"%")
                    self.ipv4host=ipv4hostparts[0]
                    self.ipv4port=String(describing:port)
                    print(self.ipv4host,self.ipv4port)
                    connection.cancel()
                }
            default:
                break
            }
        }
        connection.start(queue: .global())
    }
    
    
    
    func fetchInfo() {
        
        guard let url=URL(string:"http://\(ipv4host):\(ipv4port)/elgato/accessory-info") else {
            print("Bad URL")
            return
        }
        print(url)
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data {
                print(String(data: data, encoding: String.Encoding.utf8) ?? "")
                if let accessoryInfo = try? JSONDecoder().decode(AccessoryInfo.self, from: data) {
                    
                    self.productName=accessoryInfo.productName
                    self.hardwareBoardType=accessoryInfo.hardwareBoardType
                    self.firmwareBuildNumber=accessoryInfo.firmwareBuildNumber
                    self.firmwareVersion=accessoryInfo.firmwareVersion
                    self.serialNumber=accessoryInfo.serialNumber
                    self.displayName=accessoryInfo.displayName
                    self.features=accessoryInfo.features
                    
                } else {
                    print(error ?? "")
                }
            } else {
                print("No data")
            }
        }.resume()
        
    }
    
    func fetchState() {
        
        guard let url=URL(string:"http://\(ipv4host):\(ipv4port)/elgato/lights") else {
            print("Bad URL")
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data {
                print(String(data: data, encoding: String.Encoding.utf8) ?? "")
                if let state = try? JSONDecoder().decode(State.self, from: data) {
                    // Remember we only want the first light so....
                    DispatchQueue.main.async {
                        self.lighton=state.lights[0].on
                        self.brightness=Double(state.lights[0].brightness)
                        self.temperature=state.lights[0].temperature
                    }
                } else {
                    print(error ?? "")
                }
            } else {
                print("No data")
            }
        }.resume()
        
        
        return
    }
    
    struct SendLight: Codable {
        var lights:[LightState]
    }
    
    var updating=false
    
    func updateLight() async {
        if updating { return }
        updating=true
        
        guard let url=URL(string:"http://\(ipv4host):\(ipv4port)/elgato/lights") else {
            print("Bad URL")
            return
        }
        
        let sendlights=SendLight(lights:[LightState(on:self.lighton,brightness: Int(self.brightness), temperature: self.temperature)])
        
        guard let encoded = try? JSONEncoder().encode(sendlights) else {
            print("Failed to encode")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "PUT"
        
        do {
            let (data, _) = try await URLSession.shared.upload(for: request, from: encoded)
            let state = try JSONDecoder().decode(State.self, from: data)
            // Remember we only want the first light so....
            DispatchQueue.main.async {
                self.lighton=state.lights[0].on
                self.brightness=Double(state.lights[0].brightness)
                self.temperature=state.lights[0].temperature
            }
            updating=false
        } catch {
            print("Update Light Failed")
            print(error)
        }
        
        return
    }
}
