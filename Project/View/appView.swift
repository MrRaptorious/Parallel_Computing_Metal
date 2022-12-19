import SwiftUI

struct appView: View {
    
    var body: some View {
        
        ContentView()
            .frame(width: 1000, height:1000)
            .scaleEffect(1)
    }
}

struct appView_Previews: PreviewProvider {
    static var previews: some View {
        appView()
    }
}
