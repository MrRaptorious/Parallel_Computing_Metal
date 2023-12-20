import SwiftUI

struct appView: View {
    
    var body: some View {
        
        // Erstellt die Ansicht, um darin Shader auszuführen bzw anzuzeigen
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
