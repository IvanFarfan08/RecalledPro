//
//  ContentView.swift
//  RecalledPro
//
//  Created by Ivan Farfan on 4/29/24.
//

import SwiftUI
import RealityKit
import RealityKitContent
import GoogleGenerativeAI
import FirebaseDatabase

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var isShown: Bool
    @Binding var image: UIImage?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                parent.image = image
            }
            parent.isShown = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isShown = false
        }
    }
}

class ConfigManager {
    static func loadAPIKey() -> String? {
        guard let url = Bundle.main.url(forResource: "APIKey", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        
        return plist["APIKey"] as? String
    }
}

struct ContentView: View {
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    @State private var apiKey: String?
    @State private var model: GenerativeModel?
    @State private var firstScan = true
    @State private var didScanBegin = false
    @State private var unhideFirstScreen = false
    @State private var responseName = ""
    @State private var promptRecall = ""
    @State private var isProductAffected = false
    @State private var isProductNotAffected = false
    @State private var endOfScan = false
    @State private var textFieldInput = ""
    @State private var reasonForRecall = ""
    @State private var IDInfo = ""
    @State private var urlLink = ""
    @State private var recallVerification = ""
    
    var body: some View {
        VStack {
            if firstScan {
                Text("Welcome to Recalled Pro!")
                    .font(.title)
                    .padding()
                Text("Select a picture of a product to check if it's being recalled.")
                    .font(.subheadline)
                    .padding()
                Button("Select Picture", systemImage: "arrow.right") {
                    showingImagePicker = true
                    firstScan = false
                }
                .padding()
            }
            if unhideFirstScreen {
                Text(responseName)
                    .font(.title)
                    .padding()
                Text("We've identified a product name. Do you wish to continue?")
                    .font(.subheadline)
                    .padding()
                Button("Confirm") {
                    unhideFirstScreen = false
                    checkForRecall(objectName: responseName) { isRecalled, recallReason, identificationInfo, url in
                        reasonForRecall = recallReason ?? "Not specified"; IDInfo = identificationInfo ?? "Not specified"; urlLink = url ?? "Not specified"
                        if isRecalled {
                            generatePromptRecall(withText: "\(responseName) has been recalled for the reason: \(recallReason ?? "Not specified"), the piece of information that identifies this recall is \(identificationInfo ?? "Not specified"). Create a prompt for an user to provide the product information to see if their product is recalled via keyboard. One sentence only")
                            isProductAffected = true
                        } else {
                            isProductNotAffected = true
                            endOfScan = true
                        }
                    }
                }
                Button("Cancel") {
                    exit(0)
                }
            }
            if isProductNotAffected || recallVerification == "NO" {
                Text(responseName)
                    .font(.title)
                    .padding()
                Text("Your product is not part of any active recall issued by national authorities.")
                    .font(.subheadline)
                    .padding()
            }
            if isProductAffected {
                Text(responseName)
                    .font(.title)
                    .padding()
                Text(promptRecall)
                    .font(.subheadline)
                    .padding()
                TextField("Enter Response", text: $textFieldInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                Button("Confirm") {
                    verifyIfActiveRecall(withText: "\(responseName) has been recalled for the reason: \(reasonForRecall), the piece of information that indentifies this recall is \(IDInfo). The user responded to the prompt \(promptRecall) with: \(textFieldInput). Is the product that the user owns part of the recall? (yes or no), if the user's response does not make sense return no.")
                    isProductAffected = false
                    endOfScan = true
                }
            }
            if recallVerification == "YES" {
                Text(responseName)
                    .font(.title)
                    .padding()
                Text("Your \(responseName) is part of a recall for the following reason: \(reasonForRecall). To get more information visit:")
                Link("Recall Information", destination: URL(string: urlLink)!)
            }
            
            if endOfScan {
                Button("Start new scan") {
                    endOfScan = false; recallVerification = ""; isProductNotAffected = false; firstScan = true; didScanBegin = false
                }
            }
            
            if showingImagePicker == false && firstScan == false && didScanBegin == false {
                Text("Press confirm to process.")
                    .font(.subheadline)
                    .padding()
                Button("Confirm"){
                    GenerateProductName(withText: "Identify and return the object name considering the object visible in the camera view (provide in format Brand - Object Name)", withImage: inputImage!)
                }
            }
        }
        .padding()
        .onAppear() {
            loadModel()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(isShown: $showingImagePicker, image: $inputImage)
        }
    }
    
    private func checkForRecall(objectName: String, completion: @escaping (Bool, String?, String?, String?) -> Void) {
        let ref = Database.database().reference(withPath: "2024/recalls")
        ref.observeSingleEvent(of: .value, with: { snapshot in
            var recallFound = false
            var recallReason: String?
            var identificationInfo: String?
            var recallURL: String?
            
            // Iterate over all recall entries under each recall ID
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let dict = childSnapshot.value as? [String: Any] {
//                    print("Child Key: \(childSnapshot.key), Child Data: \(dict), Coincidence: \(dict["productName"] as! String == objectName)")
                    if let productName = dict["productName"] as? String,
                       productName == objectName {
                        recallReason = dict["recallReason"] as? String
                        identificationInfo = dict["identificationInfo"] as? String
                        recallURL = dict["url"] as? String
                        recallFound = true
                        break
                    }
                }
            }
            
            completion(recallFound, recallReason, identificationInfo, recallURL)
        }) { error in
            print(error.localizedDescription)
            completion(false, nil, nil, nil)
        }
    }
    
    private func loadModel() {
        Task {
            guard let apiKey = ConfigManager.loadAPIKey() else {
                fatalError("API Key must be set in APIKey.plist under 'APIKey'")
            }
            model = GenerativeModel(name: "gemini-1.5-pro-latest", apiKey: apiKey, requestOptions: RequestOptions(apiVersion: "v1beta"))
        }
    }
    
    
    private func GenerateProductName(withText: String, withImage: UIImage) {
        Task {
            let prompt = withText
            let image = withImage
                do {
                    let response = try await model?.generateContent(prompt, image)
                    DispatchQueue.main.async {
                        if let text = response?.text {
                            didScanBegin = true
                            unhideFirstScreen = true
                            responseName = text
                        }
                    }
                }
        }
    }
    
    private func generatePromptRecall(withText: String) {
        Task {
            let prompt = withText
                do {
                    let response = try await model?.generateContent(prompt)
                    DispatchQueue.main.async {
                        if let text = response?.text {
                            promptRecall = text
                        }
                    }
                }
        }
    }
    
    private func verifyIfActiveRecall(withText: String) {
        Task {
            let prompt = withText
                do {
                    let response = try await model?.generateContent(prompt)
                    DispatchQueue.main.async {
                        if let text = response?.text {
                            if text.uppercased().contains("YES") {
                                recallVerification = "YES"
                            } else if text.uppercased().contains("NO") {
                                recallVerification = "NO"
                            }
                        }
                    }
                }
        }
    }
}



#Preview(windowStyle: .automatic) {
    ContentView()
}
