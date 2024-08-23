import SwiftUI
import CloudKit

struct CloudView: View {
    @State private var tweets: [CKRecord] = []
    @State private var usersByID: [String: CKRecord] = [:]
    @State private var isAnimating = false
    @State private var showInputField = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var alertAction: ((String) -> Void)? = nil
    @State private var userInput = ""
    let privateDatabase = CKContainer(identifier: "iCloud.mcam3.icloud").publicCloudDatabase
    
    var body: some View {
        VStack {
            List(tweets, id: \.recordID) { tweet in
                VStack(alignment: .leading) {
                    Text(tweet["text"] as? String ?? "")
                        .font(.body).foregroundColor(.pink)
                    
                    if let userReference = tweet["tweeter"] as? CKRecord.Reference,
                       let user = usersByID[userReference.recordID.recordName] {
                        Text(user["name"] as? String ?? "")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    } else {
                        Text("Carregando usuário...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Text(tweet.creationDate != nil ? formattedDate(tweet.creationDate!) : "")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(5)
            }
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            if isAnimating {
                ProgressView()
            }
            
            HStack {
                Button("Criar Usuário") {
                    getNameAlert(title: "Usuário", message: "Digite o nome do novo usuário", action: self.createNewUser)
                }
                Button("Escrever Tweet") {
                    getNameAlert(title: "Usuário", message: "Digite o nome do usuário que postará o tweet:", action: self.checkUserBeforeWritingTweet)
                }
                Button("Atualizar Console") {
                    isAnimating = true
                    updateConsole()
                }
                Button("Limpar Banco de Dados") {
                    showDeleteConfirmation()
                }
            }
            .padding()
            
            if showInputField {
                VStack {
                    Text(alertTitle)
                        .font(.headline)
                    Text(alertMessage)
                        .font(.subheadline)
                        .padding(.bottom)
                    
                    TextField("Digite aqui...", text: $userInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    HStack {
                        Button("Cancelar") {
                            showInputField = false
                        }
                        .padding(.horizontal)
                        
                        Button("OK") {
                            if let action = alertAction {
                                action(userInput)
                            }
                            showInputField = false
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .shadow(radius: 10)
                .padding()
            }
        }
        .padding()
    }
    
    func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm dd/MM/yy"
        return df.string(from: date)
    }
    
    func getNameAlert(title: String, message: String, action: @escaping (String) -> Void) {
        alertTitle = title
        alertMessage = message
        alertAction = action
        userInput = ""
        showInputField = true
    }
    
    func showDeleteConfirmation() {
        getNameAlert(title: "Confirmar Exclusão", message: "Isso não pode ser desfeito.") { _ in
            deleteAllRecords()
        }
    }
    
    func updateConsole() {
        tweets.removeAll()
        usersByID.removeAll()
        
        let predicate = NSPredicate(value: true)
        
        // Fetch tweets
        let tweetQuery = CKQuery(recordType: "Tweet", predicate: predicate)
        tweetQuery.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let tweetOperation = CKQueryOperation(query: tweetQuery)
        
        tweetOperation.recordMatchedBlock = { id, result in
            switch result {
            case let .success(record):
                DispatchQueue.main.async {
                    self.tweets.append(record)
                    
                    // Fetch user associated with this tweet
                    if let userReference = record["tweeter"] as? CKRecord.Reference {
                        let userID = userReference.recordID.recordName
                        if self.usersByID[userID] == nil {
                            self.fetchUser(with: userReference.recordID)
                        }
                    }
                }
            case .failure:
                print("cagou")
            }

        }
        
        tweetOperation.queryResultBlock = { result in
            switch result {
            case .success(_):
                DispatchQueue.main.async {
                    self.isAnimating = false
                }
            case .failure:
                DispatchQueue.main.async {
                    self.isAnimating = false
                }
            }
        }
        
        privateDatabase.add(tweetOperation)
    }

    func fetchUser(with recordID: CKRecord.ID) {
        let userQuery = CKQuery(recordType: "User", predicate: NSPredicate(format: "recordID == %@", recordID))
        privateDatabase.fetch(withQuery: userQuery, inZoneWith: nil) { result in
            do {
                let users = try result.get().matchResults
                guard let user = try users.first?.1.get() else {
                    return
                }
                DispatchQueue.main.async {
                    self.usersByID[recordID.recordName] = user
                }
            } catch {
                print("Erro ao buscar usuário: \(error.localizedDescription)")
            }
            
        }
    }

    func checkUserBeforeWritingTweet(userName: String) {
        let predicate = NSPredicate(format: "name == %@", userName)
        let query = CKQuery(recordType: "User", predicate: predicate)
        
        privateDatabase.fetch(withQuery: query, inZoneWith: nil) { result in
            do {
                let users = try result.get().matchResults
                guard let user = try users.first?.1.get() else {
                    DispatchQueue.main.async {
                        self.alertTitle = "Erro"
                        self.alertMessage = "Usuário não encontrado."
                        self.userInput = "" // Limpar o TextField
                        self.showInputField = true
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.alertTitle = "Escrever Tweet"
                    self.alertMessage = "Digite o conteúdo do tweet:"
                    self.alertAction = { tweetText in
                        self.writeTweet(for: user, tweetText: tweetText)
                    }
                    self.userInput = "" // Limpar o TextField
                    self.showInputField = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.alertTitle = "Erro"
                    self.alertMessage = "Usuário não encontrado."
                    self.userInput = "" // Limpar o TextField
                    self.showInputField = true
                }
            }
        }
    }
    
    func writeTweet(for user: CKRecord, tweetText: String) {
        let tweet = CKRecord(recordType: "Tweet")
        tweet["text"] = tweetText
        tweet["tweeter"] = CKRecord.Reference(record: user, action: .deleteSelf)
        
        privateDatabase.save(tweet) { _, error in
            if let error = error {
                print("Erro ao salvar tweet: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    self.updateConsole()
                }
            }
        }
    }
    
    func createNewUser(userName: String) {
        let predicate = NSPredicate(format: "name == %@", userName)
        let query = CKQuery(recordType: "User", predicate: predicate)
      
        privateDatabase.fetch(withQuery: query, inZoneWith: nil) { result in
            switch result {
            case .success(let (matchResults, _)):
                // Try to get the first result
                if let (_, recordResult) = matchResults.first {
                    switch recordResult {
                    case .success(let record):
                        // Successfully fetched the record, handle it here
                        print("Record fetched: \(record)")
                    case .failure:
                        // Failed to fetch the record, show error
                        DispatchQueue.main.async {
                            self.alertTitle = "Erro"
                            self.alertMessage = "Usuário já existe."
                            self.userInput = "" // Limpar o TextField
                            self.showInputField = true
                        }
                    }
                }
            case .failure(let error):
                // Handle error
                DispatchQueue.main.async {
                    self.alertTitle = "Erro"
                    self.alertMessage = "Ocorreu um erro: \(error.localizedDescription)"
                    self.userInput = "" // Limpar o TextField
                    self.showInputField = true
                }
            }
        }
            let user = CKRecord(recordType: "User")
            user["name"] = userName
            
            self.privateDatabase.save(user) { _, error in
                if let error = error {
                    print("Erro ao criar usuário: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self.updateConsole()
                    }
                }
            }
        }
    
    func deleteAllRecords() {
        let query = CKQuery(recordType: "Tweet", predicate: NSPredicate(value: true))
        
        privateDatabase.fetch(withQuery: query, inZoneWith: nil) { result in
            switch result {
            case .success(let (matchResults, _)):
                for (_, recordResult) in matchResults {
                    switch recordResult {
                    case .success(let record):
                        self.privateDatabase.delete(withRecordID: record.recordID) { _, error in
                            if let error = error {
                                print("Erro ao deletar record: \(error.localizedDescription)")
                            }
                        }
                    case .failure(let error):
                        print("Erro ao buscar record: \(error.localizedDescription)")
                    }
                }
                
                DispatchQueue.main.async {
                    self.updateConsole()
                }
                
            case .failure(let error):
                print("Erro ao realizar busca: \(error.localizedDescription)")
            }
        }

    }
}

#Preview {
    CloudView()
}
