import SwiftUI
import SwiftData

/// Manage your golf bag — 14 clubs with swing thoughts and equipment tracking
struct BagView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bags: [GolfBag]
    @Query private var equipmentLogs: [EquipmentLog]

    @State private var editingClub: BagClub?
    @State private var showAddEquipment = false

    private var bag: GolfBag? { bags.first }

    var body: some View {
        List {
            // Clubs in bag
            Section("My Clubs (\(bag?.clubs.count ?? 0)/14)") {
                if let bag {
                    ForEach(bag.clubs) { club in
                        Button {
                            editingClub = club
                        } label: {
                            HStack {
                                Text(club.club.displayName)
                                    .font(.subheadline.bold())
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if let brand = club.brand {
                                        Text(brand)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let thought = club.swingThought, !thought.isEmpty {
                                        Text(thought)
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                            .italic()
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Button("Set Up My Bag") {
                        let newBag = GolfBag()
                        modelContext.insert(newBag)
                    }
                }
            }

            // Equipment log
            Section("Equipment Changes") {
                ForEach(equipmentLogs.sorted(by: { $0.dateStarted > $1.dateStarted }).prefix(10), id: \.id) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(log.itemType.capitalized)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(log.itemName)
                                .font(.subheadline)
                        }
                        HStack {
                            Text("Started: \(log.dateStarted.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if let club = log.club {
                                Text("(\(club))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Button {
                    showAddEquipment = true
                } label: {
                    Label("Log Equipment Change", systemImage: "plus")
                }
            }
        }
        .navigationTitle("My Bag")
        .sheet(item: $editingClub) { club in
            EditClubSheet(bag: bag!, club: club, modelContext: modelContext)
        }
        .sheet(isPresented: $showAddEquipment) {
            AddEquipmentSheet(modelContext: modelContext)
        }
    }
}

struct EditClubSheet: View {
    let bag: GolfBag
    let club: BagClub
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var brand: String
    @State private var model: String
    @State private var swingThought: String

    init(bag: GolfBag, club: BagClub, modelContext: ModelContext) {
        self.bag = bag
        self.club = club
        self.modelContext = modelContext
        _brand = State(initialValue: club.brand ?? "")
        _model = State(initialValue: club.model ?? "")
        _swingThought = State(initialValue: club.swingThought ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Club") {
                    Text(club.club.displayName).font(.headline)
                }

                Section("Details") {
                    TextField("Brand (e.g., Titleist)", text: $brand)
                    TextField("Model (e.g., T200)", text: $model)
                }

                Section("Swing Thought") {
                    TextField("e.g., Slow takeaway", text: $swingThought)
                    Text("This reminder pops up when you use this club")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit \(club.club.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var clubs = bag.clubs
                        if let idx = clubs.firstIndex(where: { $0.id == club.id }) {
                            clubs[idx] = BagClub(
                                club: club.club,
                                brand: brand.isEmpty ? nil : brand,
                                model: model.isEmpty ? nil : model,
                                swingThought: swingThought.isEmpty ? nil : swingThought
                            )
                            bag.clubs = clubs
                        }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

struct AddEquipmentSheet: View {
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss

    @State private var itemType = "ball"
    @State private var itemName = ""
    @State private var club = ""
    @State private var notes = ""

    let types = ["ball", "grip", "shaft", "club", "glove", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $itemType) {
                    ForEach(types, id: \.self) { Text($0.capitalized) }
                }

                TextField("Name (e.g., Pro V1)", text: $itemName)
                TextField("Club (optional)", text: $club)
                TextField("Notes", text: $notes)
            }
            .navigationTitle("Log Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let log = EquipmentLog(
                            itemType: itemType,
                            itemName: itemName,
                            club: club.isEmpty ? nil : club,
                            notes: notes.isEmpty ? nil : notes
                        )
                        modelContext.insert(log)
                        dismiss()
                    }
                    .bold()
                    .disabled(itemName.isEmpty)
                }
            }
        }
    }
}
