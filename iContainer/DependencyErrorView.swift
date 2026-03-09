import SwiftUI

struct DependencyErrorView: View {
    let errors: [DependencyError]
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.yellow)
            
            Text("Setup Required")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("The following dependencies are missing:")
                .font(.headline)
            
            ForEach(errors) { error in
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error.description)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Text("Please install the required tools to continue.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DependencyErrorView_Previews: PreviewProvider {
    static var previews: some View {
        DependencyErrorView(errors: [.cliMissing])
    }
}
