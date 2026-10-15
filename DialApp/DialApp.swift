import SwiftUI
import Contacts
import CoreData

enum CallType: Int16 {
    case outgoing = 0, incoming = 1, missed = 2
    var text: String { switch self { case .outgoing: return "呼出"; case .incoming: return "呼入"; case .missed: return "未接" } }
    var color: Color { switch self { case .outgoing: return .green; case .incoming: return .blue; case .missed: return .red } }
}

@objc(CallLog)
class CallLog: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var phoneNumber: String
    @NSManaged var name: String?
    @NSManaged var date: Date
    @NSManaged var callType: Int16
    @NSManaged var duration: Double
}
extension CallLog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CallLog> { NSFetchRequest<CallLog>(entityName: "CallLog") }
}

class CoreDataStack {
    static let shared = CoreDataStack()
    let container: NSPersistentContainer
    init() {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "CallLog"
        entity.managedObjectClassName = NSStringFromClass(CallLog.self)
        let attrs: [(String, NSAttributeType, Bool)] = [
            ("id", .UUIDAttributeType, false), ("phoneNumber", .stringAttributeType, false),
            ("name", .stringAttributeType, true), ("date", .dateAttributeType, false),
            ("callType", .integer16AttributeType, false), ("duration", .doubleAttributeType, false)]
        entity.properties = attrs.map { name, type, opt in
            let a = NSAttributeDescription(); a.name = name; a.attributeType = type; a.isOptional = opt; return a
        }
        model.entities = [entity]
        container = NSPersistentContainer(name: "CallLogModel", managedObjectModel: model)
        container.loadPersistentStores { _, e in if let e = e as NSError? { fatalError("CoreData: \(e)") } }
    }
    func save() { let c = container.viewContext; if c.hasChanges { try? c.save() } }
}

class ContactManager: ObservableObject {
    static let shared = ContactManager()
    @Published var contacts: [CNContact] = []
    func requestAccess() {
        CNContactStore().requestAccess(for: .contacts) { g, _ in
            DispatchQueue.main.async { if g { self.fetch() } }
        }
    }
    func fetch() {
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        var list = [CNContact]()
        DispatchQueue.global().async {
            try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in list.append(c) }
            DispatchQueue.main.async { self.contacts = list }
        }
    }
    func search(_ k: String) -> [CNContact] {
        guard !k.isEmpty else { return [] }
        let l = k.lowercased()
        return contacts.filter {
            ($0.givenName + $0.familyName).lowercased().contains(l) ||
            $0.phoneNumbers.map { $0.value.stringValue }.joined().contains(k)
        }
    }
}

struct ContentView: View {
    @State private var tab = 0
    @StateObject var cm = ContactManager()
    var body: some View {
        TabView(selection: $tab) {
            DialView().tabItem { Label("拨号", systemImage: "phone") }.tag(0)
            ContactListView().tabItem { Label("通讯录", systemImage: "person.fill") }.tag(1)
            RecordGroupView().tabItem { Label("最近", systemImage: "clock.fill") }.tag(2)
        }.accentColor(.blue).environmentObject(cm).onAppear { cm.requestAccess() }
    }
}

struct DialView: View {
    @EnvironmentObject var cm: ContactManager
    @Environment(\.managedObjectContext) var ctx
    @State private var input = ""
    @State private var showAdd = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    TextField("输入号码或搜索联系人", text: $input).font(.system(size: 22)).keyboardType(.numberPad)
                        .padding(12).background(Color(.systemGray6)).cornerRadius(10)
                    if !input.isEmpty { Button { input = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) } }
                }.padding(.horizontal)
                let res = cm.search(input)
                if !res.isEmpty {
                    List(res) { c in
                        Button { call(c.phoneNumbers.first!.value.stringValue, name: c.givenName+" "+c.familyName) } label: {
                            HStack { Text(c.givenName+" "+c.familyName); Spacer(); Text(c.phoneNumbers.first!.value.stringValue).foregroundColor(.secondary) }
                        }
                    }.listStyle(.plain).frame(maxHeight: 200)
                }
                Spacer()
                DialPad(input: $input)
                HStack(spacing: 40) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundColor(.gray).frame(width: 64, height: 64) }
                    Button { call(input) } label: {
                        Image(systemName: "phone.fill").font(.title).foregroundColor(.white)
                            .frame(width: 64, height: 64).background(Color.green).clipShape(Circle())
                    }
                }.padding(.bottom, 24)
            }.navigationTitle("拨号").sheet(isPresented: $showAdd) { AddRecordView() }
        }
    }
    func call(_ phone: String, name: String? = nil) {
        guard !phone.isEmpty, let url = URL(string: "tel://\(phone)") else { return }
        UIApplication.shared.open(url)
        let log = CallLog(context: ctx)
        log.id = UUID(); log.phoneNumber = phone; log.name = name; log.date = Date(); log.callType = 0; log.duration = 0
        CoreDataStack.shared.save()
    }
}

struct DialPad: View {
    @Binding var input: String
    let keys = [["1","2","3"],["4","5","6"],["7","8","9"],["*","0","#"]]
    var body: some View {
        VStack(spacing: 14) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(row, id: \.self) { k in
                        Button { input += k } label: {
                            Text(k).font(.system(size: 30)).frame(width: 68, height: 68)
                                .background(Color(.systemGray5)).clipShape(Circle())
                        }
                    }
                }
            }
        }
    }
}

struct AddRecordView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var ctx
    @State private var phone = "", name = ""
    @State private var type: CallType = .incoming
    @State private var dur = 0
    var body: some View {
        NavigationStack {
            Form {
                Section("电话号码") { TextField("输入号码", text: $phone).keyboardType(.numberPad) }
                Section("备注姓名") { TextField("可选", text: $name) }
                Section("类型") {
                    Picker("", selection: $type) {
                        Text("呼入").tag(CallType.incoming); Text("呼出").tag(CallType.outgoing); Text("未接").tag(CallType.missed)
                    }.pickerStyle(.segmented)
                }
                Section("时长") { Stepper("\(dur) 秒", value: $dur, in: 0...3600) }
            }.navigationTitle("添加通话记录").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !phone.isEmpty else { return }
                        let log = CallLog(context: ctx)
                        log.id = UUID(); log.phoneNumber = phone; log.name = name.isEmpty ? nil : name
                        log.date = Date(); log.callType = type.rawValue; log.duration = Double(dur)
                        CoreDataStack.shared.save(); dismiss()
                    }
                }
            }
        }
    }
}

struct ContactListView: View {
    @EnvironmentObject var cm: ContactManager
    var body: some View {
        NavigationStack {
            List(cm.contacts, id: \.identifier) { c in
                NavigationLink { ContactDetailView(c: c) } label: {
                    VStack(alignment: .leading) {
                        Text(c.givenName+" "+c.familyName)
                        Text(c.phoneNumbers.first?.value.stringValue ?? "").font(.caption).foregroundColor(.secondary)
                    }
                }
            }.navigationTitle("通讯录")
        }
    }
}

struct ContactDetailView: View {
    let c: CNContact
    @FetchRequest var logs: FetchedResults<CallLog>
    init(c: CNContact) {
        self.c = c
        let p = c.phoneNumbers.first?.value.stringValue ?? ""
        _logs = FetchRequest(sortDescriptors: [.init(key: "date", ascending: false)],
                             predicate: NSPredicate(format: "phoneNumber == %@", p))
    }
    var body: some View {
        List {
            ForEach(logs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.date.formatted(date: .abbreviated, time: .shortened))
                    HStack {
                        Text(CallType(rawValue: log.callType)?.text ?? "").foregroundColor(CallType(rawValue: log.callType)?.color).font(.headline)
                        Spacer(); Text("\(Int(log.duration))秒").foregroundColor(.secondary)
                    }
                }
            }
        }.navigationTitle(c.givenName+" "+c.familyName).toolbar {
            Button {
                guard let p = c.phoneNumbers.first?.value.stringValue, let url = URL(string: "tel://\(p)") else { return }
                UIApplication.shared.open(url)
            } label: { Label("回拨", systemImage: "phone") }
        }
    }
}

struct RecordGroupView: View {
    @Environment(\.managedObjectContext) var ctx
    @FetchRequest(sortDescriptors: [SortDescriptor(\.date, order: .reverse)]) var allLogs: FetchedResults<CallLog>
    var group: [String: [CallLog]] { Dictionary(grouping: allLogs) { $0.phoneNumber } }
    var exportText: String {
        var s = "===== 通话记录导出 =====\n\n"
        for (p, logs) in group {
            s += "号码: \(p)  姓名: \(logs.first?.name ?? p)\n"
            for log in logs {
                s += "  \(log.date.formatted())  \(CallType(rawValue: log.callType)?.text ?? "")  \(Int(log.duration))秒\n"
            }
            s += "\n"
        }
        return s
    }
    var body: some View {
        NavigationStack {
            List(group.keys.sorted(), id: \.self) { p in
                let logs = group[p]!
                NavigationLink { RecordDetailView(phone: p, logs: logs) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(logs.first?.name ?? p).font(.system(size: 16, weight: .semibold))
                        HStack {
                            Text(CallType(rawValue: logs.first?.callType ?? 0)?.text ?? "")
                                .foregroundColor(CallType(rawValue: logs.first?.callType ?? 0)?.color)
                            Text(logs.first?.date.formatted(date: .abbreviated, time: .shortened) ?? "")
                        }.font(.caption).foregroundColor(.secondary)
                    }
                    Spacer(); Text("\(logs.count)次").foregroundColor(.gray)
                }
            }.navigationTitle("最近通话").toolbar {
                ShareLink(item: exportText) { Label("导出", systemImage: "square.and.arrow.up") }
            }
        }
    }
}

struct RecordDetailView: View {
    let phone: String
    let logs: [CallLog]
    @Environment(\.managedObjectContext) var ctx
    var body: some View {
        List {
            ForEach(logs) { log in
                VStack(alignment: .leading, spacing: 6) {
                    Text(log.date.formatted(date: .complete, time: .standard)).font(.subheadline)
                    HStack {
                        Text(CallType(rawValue: log.callType)?.text ?? "")
                            .foregroundColor(CallType(rawValue: log.callType)?.color).font(.headline)
                        Spacer(); Text("时长 \(Int(log.duration)) 秒").foregroundColor(.secondary)
                    }
                }.padding(.vertical, 4)
            }.onDelete(perform: delete)
        }.navigationTitle(phone).toolbar {
            EditButton()
            Button {
                guard let url = URL(string: "tel://\(phone)") else { return }
                UIApplication.shared.open(url)
            } label: { Image(systemName: "phone.fill") }
        }
    }
    func delete(_ idx: IndexSet) { idx.forEach { ctx.delete(logs[$0]) }; CoreDataStack.shared.save() }
}

@main
struct DialAppMain: App {
    var body: some Scene {
        WindowGroup {
            ContentView().environment(\.managedObjectContext, CoreDataStack.shared.container.viewContext)
        }
    }
}
