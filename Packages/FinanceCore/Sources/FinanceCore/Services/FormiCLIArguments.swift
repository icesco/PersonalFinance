import Foundation

public enum FormiCLIArguments {
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }
    public static func parse(_ arguments: [String], read: (String) throws -> Data,
                             today: String) throws -> FormiCLIRequest {
        guard let command = arguments.first,
              ["accounts", "categories", "add", "import", "preview", "category-create", "category-update"].contains(command) else {
            throw Failure("Comando sconosciuto. Usa formi --help.")
        }
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var file: String?
        var i = 1
        let categoryCommand = ["category-create", "category-update"].contains(command)
        let valueOptions: Set<String> = categoryCommand
            ? ["--book", "--category", "--name", "--color", "--icon", "--parent", "--type", "--active", "--request-id", "--revision"]
            : command == "add"
            ? ["--account", "--category", "--amount", "--currency", "--date", "--description", "--request-id", "--type", "--book"]
            : ["--book"]
        let flagOptions: Set<String> = categoryCommand ? ["--yes", "--json"]
            : command == "categories" ? ["--include-archived", "--json"]
            : ["add", "import"].contains(command)
            ? ["--yes", "--allow-duplicates", "--json"] : ["--json"]
        while i < arguments.count {
            let argument = arguments[i]
            if flagOptions.contains(argument) {
                guard flags.insert(argument).inserted else { throw Failure("Parametro ripetuto: \(argument)") }
                i += 1
            } else if valueOptions.contains(argument) {
                guard options[argument] == nil, i + 1 < arguments.count,
                      !arguments[i + 1].hasPrefix("--") else { throw Failure("Parametro mancante o ripetuto: \(argument)") }
                options[argument] = arguments[i + 1]; i += 2
            } else if ["import", "preview"].contains(command), file == nil,
                      argument == "-" || !argument.hasPrefix("-") {
                file = argument; i += 1
            } else { throw Failure("Parametro sconosciuto: \(argument)") }
        }
        func uuid(_ key: String, required: Bool = false) throws -> UUID? {
            guard let value = options[key] else {
                if required { throw Failure("Parametro richiesto: \(key)") }
                return nil
            }
            guard let id = UUID(uuidString: value) else { throw Failure("UUID non valido: \(key)") }
            return id
        }
        var movements: [FormiCLIMovement] = []
        if command == "add" {
            guard let amount = options["--amount"], let currency = options["--currency"] else {
                throw Failure("add richiede --account, --amount e --currency.")
            }
            movements = [FormiCLIMovement(requestID: try uuid("--request-id") ?? UUID(),
                accountID: try uuid("--account", required: true)!, categoryID: try uuid("--category"),
                type: options["--type"] ?? "expense", amount: amount, currency: currency,
                date: options["--date"] ?? today, description: options["--description"])]
        } else if ["import", "preview"].contains(command) {
            guard let file else { throw Failure("Specifica un file JSON oppure - per stdin.") }
            let data = try read(file)
            guard data.count <= FormiCLIWire.maxBytes else { throw Failure("JSON troppo grande (massimo 2 MB).") }
            let decoder = FormiCLIWire.decoder()
            if let array = try? decoder.decode([FormiCLIMovement].self, from: data) { movements = array }
            else { movements = [try decoder.decode(FormiCLIMovement.self, from: data)] }
            guard !movements.isEmpty, movements.count <= 500 else { throw Failure("Usa da 1 a 500 movimenti.") }
        }
        var request = FormiCLIRequest(command: command, movements: movements, commit: flags.contains("--yes"),
            allowDuplicates: flags.contains("--allow-duplicates"), bookID: try uuid("--book", required: categoryCommand))
        request.includeArchived = flags.contains("--include-archived")
        if categoryCommand {
            if let type = options["--type"], !["expense", "income", "both"].contains(type) {
                throw Failure("--type deve essere expense, income o both.")
            }
            var active: Bool?
            if let value = options["--active"] {
                guard ["true", "false"].contains(value) else { throw Failure("--active deve essere true o false.") }
                active = value == "true"
            }
            if let parent = options["--parent"], parent != "none", UUID(uuidString: parent) == nil {
                throw Failure("--parent richiede un UUID oppure none.")
            }
            if command == "category-create" {
                guard options["--name"] != nil, options["--category"] == nil else {
                    throw Failure("category-create richiede --name e non accetta --category.")
                }
            } else {
                guard ["--name", "--color", "--icon", "--parent", "--type", "--active"].contains(where: { options[$0] != nil }) else {
                    throw Failure("Specifica almeno un campo da modificare.")
                }
            }
            request.categoryMutation = FormiCLICategoryMutation(requestID: try uuid("--request-id", required: true)!,
                categoryID: try uuid("--category", required: command == "category-update"),
                name: options["--name"], color: options["--color"], icon: options["--icon"],
                parent: options["--parent"], type: options["--type"], active: active, revision: options["--revision"])
        }
        return request
    }
}
