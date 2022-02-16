//
//  ContentView.swift
//  Elgaric
//
//  Created by Dj Walker-Morgan on 11/02/2022.
//

import SwiftUI

struct ContentView: View {
    
    @StateObject var lt=LightTracker()
    
    var body: some View {
        VStack {
            HStack {
                Button{ allOn() } label:{Text("All On")}
                Button{ allOff() } label:{Text("All Off")}
            }.padding(10)
        List(lt.lights.indices, id: \.self) { index in
            LightCell(light: lt.lights[index])
        }.task {
            lt.start()
        }
        }.frame(width: 500.0, height: 300.0)
    }
    
    func allOn() {

            lt.lights.forEach { light in
            light.lighton=1
            Task {
                await light.updateLight()
            }
        }
    }
    
    func allOff() {
            lt.lights.forEach { light in
            light.lighton=0
                Task {
                    await light.updateLight()
                }
            }
    }
}

extension Binding {
    func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                self.wrappedValue = newValue
                handler(newValue)
            }
        )
    }
}

struct LightCell: View {
    @ObservedObject var light: RestLight
    
    
    var body: some View {
        HStack {
            Button(action:{
                Task {
                    light.lighton=abs(light.lighton-1)
                    await light.updateLight()
                }
            },label:{
                if(light.lighton==1) {
                    Image(systemName: "circle.fill")
                } else {
                    Image(systemName: "circle")
                }
                Text(light.name)
            })
            Slider(value:$light.brightness.onChange(updateBrightness), in:0.0...100.0, step:10)
            
        }
    }
    
    func updateBrightness(d:Double) {
        Task {
            await light.updateLight()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            
    }
}
