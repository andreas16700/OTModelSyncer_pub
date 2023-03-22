import XCTest
import PowersoftKit
import ShopifyKit
import MockShopifyClient
import MockPowersoftClient
@testable import OTModelSyncer



final class OTModelSyncerTests: XCTestCase {
	
	static func setupServers()async throws{
		let xSeed:UInt64 = 3199077918806463242
		let ySeed:UInt64 = 11403738689752549865
		var gen: RandomNumberGenerator = Xorshift128Plus(xSeed: xSeed, ySeed: ySeed)
		let psClient = MockPsClient(baseURL: URL(string: "http://localhost:8081")!)
		let shClient = MockShClient(baseURL: URL(string: "http://localhost:8082")!)
		let modelCount = 100
		print("Generating \(modelCount) models")
		let r = await psClient.generateModels(modelCount: modelCount, xSeed: xSeed, ySeed: ySeed)
		XCTAssertTrue(r)
		let pNum = Int.random(in: 0...modelCount, using: &gen)
		let fNum = Int.random(in: 0..<modelCount, using: &gen)
		print("\(pNum) and \(fNum) models shall be partially and fully synced on the SH server respectively")
		print("Retrieving \(pNum+fNum) models from the PS server")
		let allModelsOpt = await psClient.getFirstModelsAndTheirStocks(count: pNum+fNum)
		let allModels = try XCTUnwrap(allModelsOpt)
		print("Converting \(pNum) models into partially synced products")
		let pProducts = allModels[0..<pNum].map{
			var stocks = $0.stocks
			let product = SHProduct.partiallySynced(with: $0.model, stocksByItemCode: &stocks, using: &gen)
			return ProductAndItsStocks(product: product, stocksBySKU: stocks)
		}
		print("Converting \(fNum) models into partially synced products")
		let fModels = allModels[pNum...]
		let fProducts = fModels.map{modelAndStocks in
			let product = try! modelAndStocks.model.getAsNewProduct()
			return ProductAndItsStocks(product: product, stocksBySKU: modelAndStocks.stocks)
		}
		let pfProducts = pProducts + fProducts
		print("Uploading \(pfProducts.count) products and their stocks to the SH server")
		let r2 = await shClient.createNewProductsWithStocks(stuff: pfProducts)
		XCTAssertTrue(r2)
		
		
	}
	
	override func setUp() async throws {
		try await Self.setupServers()
	}
	override func tearDown() async throws {
		let psClient = MockPsClient(baseURL: URL(string: "http://localhost:8081")!)
		let shClient = MockShClient(baseURL: URL(string: "http://localhost:8082")!)
		let r = await psClient.reset()
		XCTAssertTrue(r)
		let r2 = await shClient.reset()
		XCTAssertTrue(r2)
	}
	actor SaveContainer{
		var syncs = [String: SingleModelSync]()
		var modelsSync: ModelsSync? = nil
		func getSync(modelCode: String)async->SingleModelSync?{
			return self.syncs[modelCode]
		}
		func save(_ s: SingleModelSync)async->Bool{
			self.syncs[s.source.modelCode]=s
			return true
		}
		func saveModelsSync(_ s: ModelsSync)async->Bool{
			self.modelsSync = s
			return true
		}
		#if !os(Linux)
		func saveToDisk(){
			let data = try! encoder.encode(syncs)
			try! data.write(to: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appending(path: "allModelsSync.json"))
		}
		#endif
	}
	let saveContainer = SaveContainer()
	let psClient = MockPsClient(baseURL: URL(string: "http://localhost:8081")!)
	let shClient = MockShClient(baseURL: URL(string: "http://localhost:8082")!)
	let dualOptionedModels = ["PMDO", "E310000", "KY12150", "P984", "KFM1130A", "104461"]
	let triOptionedModels = ["A510271", "7851", "AW131A", "7645A", "7750"]

	func syncDesc(_ s: ModelsSync){
		func printDict(_ name: String, d: [String: String]?){
			guard let d else {print(name, " is nil!"); return}
			print(name)
			for (key,value) in d{
				print(key,": ",value)
			}
		}
		printDict("syncIDByModelCode", d: s.syncIDByModelCode)
		printDict("interestingDoneSyncs", d: s.interestingDoneSyncs)
		printDict("uninterestingDoneSyncs", d: s.uninterestingDoneSyncs)
	}
	
	func testSyncAllModels()async throws{
		let modelsSyncer = ModelsSyncer(ps: psClient, sh: shClient, individualSyncSaveMethod: saveContainer.save, saveMethod: saveContainer.saveModelsSync)
		let _modelsSync = await modelsSyncer.sync()
		let modelsSync = try XCTUnwrap(_modelsSync)
		XCTAssertTrue(modelsSync.failedSyncs?.isEmpty ?? true)
		XCTAssertTrue(modelsSync.inQueueSyncs?.isEmpty ?? true)
		XCTAssertFalse(modelsSync.uninterestingDoneSyncs?.isEmpty ?? true)
		let uninterestingCount = modelsSync.uninterestingDoneSyncs?.count ?? 0
		let interestingCount = modelsSync.interestingDoneSyncs?.count ?? 0
		let totalSyncCount = modelsSync.syncIDByModelCode?.count ?? 0
		XCTAssertEqual(uninterestingCount+interestingCount, totalSyncCount)
		XCTAssertFalse(modelsSync.isInProgress)
		XCTAssertEqual(modelsSync.metadata.state, .done)
		XCTAssertNil(modelsSync.metadata.failReason)
		#if !os(Linux)
		await saveContainer.saveToDisk()
		#endif
	}
	#if !os(Linux)
	func decodeLocalInDLFolder<T: Decodable>(name: String, type: T.Type)->T{
		return try! JSONDecoder().decode(T.self, from: try! Data(contentsOf: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appending(path: name+".json")))
	}
	func writeLocalToDLFolder<T: Encodable>(name: String, thing: T){
		try! encoder.encode(thing).write(to: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appending(path: name+".json"))
	}
	#endif
	func makeSyncer(for modelCode: String, with data: ([PSItem], [PSListStockStoresItem]))->SingleModelSyncer{
		return .init(modelCode: modelCode, ps: psClient, sh: shClient, psDataToUse: data, saveMethod: saveContainer.save)
	}
	func makeSyncer(for modelCode: String, with data: PSData)->SingleModelSyncer{
		return .init(modelCode: modelCode, ps: psClient, sh: shClient, psDataToUse: (data.model, data.stocks), saveMethod: saveContainer.save)
	}
	func unwrapValueFromOp<T>(_ op: ()async throws->T?)async throws->T{
		let _opt = try await op()
		let value = try XCTUnwrap(_opt)
		return value
	}
	func getPSDataSanitizedForTesting(modelCode: String)async throws -> PSData{
		let model = try await unwrapValueFromOp{
			return await psClient.getModel(modelCode: modelCode)
		}
		let stocks = try await model.asyncMap{item in
			return try await unwrapValueFromOp{return await psClient.getStock(for: item.itemCode365)}
		}
		return model.makeFake(withStocks: stocks)
	}

	func workWithEphemeralSyncerForSanitizableModel(modelCode: String, _ work: (PSData, SingleModelSyncer)async throws->())async throws{
		let psData = try await getPSDataSanitizedForTesting(modelCode: modelCode)
		let newModelCode = try XCTUnwrap(psData.model.first?.modelCode365)
		let syncer = makeSyncer(for: newModelCode, with: psData)
		do{
			try await work(psData, syncer)
		}catch{

		}
		let sync = await syncer.data
		print("Deleting created product (if any)")
		if let product = sync.source.product, let id=product.id{
			print("Will delete created product with id: \(id)")
			let wasDeleted = await shClient.deleteProduct(id: id)
			XCTAssertTrue(wasDeleted)
			print("Deleted \(id)")
		}
	}
	func testSyncerPSDataIntegrity(_ sync: SingleModelSync, psData: PSData)throws{
		let modelFromSyncer = Set(try XCTUnwrap(sync.source.modelItems?.values.map{try XCTUnwrap($0.psItem)}))
		let stocksFromSyncer = Set(try XCTUnwrap(sync.source.modelItems?.values.map{try XCTUnwrap($0.psStock)}))

		let originalModel = Set(psData.model)
		let originalStocks = Set(psData.stocks)
		XCTAssertEqual(modelFromSyncer, originalModel)
		XCTAssertEqual(stocksFromSyncer, originalStocks)
	}
	func testSyncDoesntHaveErrors(_ sync: SingleModelSync, psData: PSData? = nil)async throws{
		XCTAssertNil(sync.metadata.errors)
		XCTAssertNil(sync.metadata.syncErrors)
		XCTAssertNil(sync.metadata.unknownErrors)
		for (kind, state) in sync.metadata.states{
			print("Checking state of \(kind)")
			XCTAssertEqual(state, .done)
		}
		if let original = psData{
			try testSyncerPSDataIntegrity(sync, psData: original)
		}
		let _saved = await saveContainer.getSync(modelCode: sync.source.modelCode)
		let saved = try XCTUnwrap(_saved)
		XCTAssertEqual(saved, sync)
	}
	func testIsSynced(modelCode: String, psData: PSData)async throws{
		//If it's synced the syncer should have no updates and do nothing.
		let syncer = makeSyncer(for: modelCode, with: psData)
		let sync = try await unwrapValueFromOp{return await syncer.sync()}
		try testSyncerPSDataIntegrity(sync, psData: psData)
		XCTAssertNil(sync.updates)
	}
	//Seems currently Shopify doesn't allow removing options via REST api. Replies with "could not delete option because it has more than 1 value"
//	func testRemoveThirdOption()async throws{
//		let triOptionedModelCode = try XCTUnwrap(triOptionedModels.randomElement())
//		try await workWithEphemeralSyncerForSanitizableModel(modelCode: triOptionedModelCode){psData, syncer in
//			let sync1 = try await unwrapValueFromOp{return await syncer.sync()}
//			try testSyncerPSDataIntegrity(sync1, psData: psData)
//
//			let modelWithTwoOptions = psData.model.removeThirdOptionAsSuffixToColorName()
//			let computedOptions2 = try modelWithTwoOptions.getSHOptions()
//			XCTAssertEqual(computedOptions2.count, 2)
//			let newPSData: PSData = .init(model: modelWithTwoOptions, stocks: psData.stocks)
//
//			let newSyncer = SingleModelSyncer(modelCode: sync1.source.modelCode, model: newPSData.model, psStocks: newPSData.stocks)
//			let sync2 = try await unwrapValueFromOp{return await newSyncer.sync()}
//
//			try testSyncerPSDataIntegrity(sync2, psData: newPSData)
//			let product = try XCTUnwrap(sync2.source.product)
//			let options = try XCTUnwrap(product.options)
//			XCTAssertEqual(options.count, 2)
//
//			let computedOptions = try modelWithTwoOptions.getSHOptions()
//			for computedOption in computedOptions {
//				let equivalentOption = try XCTUnwrap(options.first(where:{$0.name == computedOption.name}))
//				XCTAssertEqual(equivalentOption.position, computedOption.position)
//				XCTAssertEqual(Set(equivalentOption.values), Set(computedOption.values))
//			}
//			try await  testIsSynced(modelCode: triOptionedModelCode, psData: newPSData)
//		}
//	}
	func testAddThirdOption()async throws{
		let dualOptionedModelCode = try XCTUnwrap(dualOptionedModels.randomElement())
		try await workWithEphemeralSyncerForSanitizableModel(modelCode: dualOptionedModelCode){psData, syncer in
			let sync1 = try await unwrapValueFromOp{return await syncer.sync()}
			try testSyncerPSDataIntegrity(sync1, psData: psData)

			let modelWithThirdOption = psData.model.addThirdOptionAsSuffixToColorName()
			let newPSData: PSData = .init(model: modelWithThirdOption, stocks: psData.stocks)

			let newSyncer = makeSyncer(for: sync1.source.modelCode, with: (modelWithThirdOption, psData.stocks))
			let sync2 = try await unwrapValueFromOp{return await newSyncer.sync()}

			try testSyncerPSDataIntegrity(sync2, psData: newPSData)
			let product = try XCTUnwrap(sync2.source.product)
			let options = try XCTUnwrap(product.options)
			XCTAssertEqual(options.count, 3)

			let computedOptions = try modelWithThirdOption.getSHOptions()
			for computedOption in computedOptions {
				let equivalentOption = try XCTUnwrap(options.first(where:{$0.name == computedOption.name}))
				XCTAssertEqual(equivalentOption.position, computedOption.position)
				XCTAssertEqual(Set(equivalentOption.values), Set(computedOption.values))
			}
			try await  testIsSynced(modelCode: dualOptionedModelCode, psData: newPSData)
		}
	}
	func testCreateDualOptionedModel()async throws{
		let modelCodes = dualOptionedModels
		let modelCode = try XCTUnwrap(modelCodes.randomElement())
		try await workWithEphemeralSyncerForSanitizableModel(modelCode: modelCode){psData, syncer in
			let sync = try await unwrapValueFromOp{return await syncer.sync()}
			try await testSyncDoesntHaveErrors(sync, psData: psData)
		}
	}
	func testCreateTriOptionedModel()async throws{
		let modelCodes = triOptionedModels
		let modelCode = try XCTUnwrap(modelCodes.randomElement())
		try await workWithEphemeralSyncerForSanitizableModel(modelCode: modelCode){psData, syncer in
			let sync = try await unwrapValueFromOp{return await syncer.sync()}
			try await testSyncDoesntHaveErrors(sync, psData: psData)
		}
	}

}
struct PSData{
	let model: [PSItem]
	let stocks: [PSListStockStoresItem]
}
extension Array where Element==PSItem{
	func removeThirdOptionAsSuffixToColorName()->Self{
		return map{
			let cleaned = $0.getCleanColorValue()
			return $0.withChangedProperty(\.colorName, to: cleaned)
		}
	}
	func addThirdOptionAsSuffixToColorName(separator: String = "_", value1: String = "L", value2: String = "R")->Self{
		return map{
			let original = $0.colorName
			let suffixForOrientation = separator + (Bool.random() ? value1: value2)
			return $0.withChangedProperty(\.colorName, to: original+suffixForOrientation)
		}
	}
	func makeFake(withStocks stocks: [PSListStockStoresItem])->PSData{
		let modelSuffix = UUID().uuidString.prefix(3)
		let newModelCode = randomElement()!.modelCode365+modelSuffix
		var newStocks = [PSListStockStoresItem]()
		let newModel = map{item in
			let newItem = item.makeFake(newModelCode: newModelCode)
			if var stock = stocks.first(where: {$0.itemCode365==item.itemCode365}){
				stock.itemCode365 = newItem.itemCode365
				stock.modelCode365 = newItem.modelCode365
				newStocks.append(stock)
			}
			return newItem
		}
		return .init(model: newModel, stocks: newStocks)
	}
}
extension PSItem{
	func withChangedProperty<T>(_ kp: WritableKeyPath<Self,T>, to newValue: T)->Self{
		var m = self
		m[keyPath: kp]=newValue
		return m
	}
	func makeFake(newModelCode: String)->Self{
		var item = self
		item.itemCode365+=UUID().uuidString.prefix(3)
		item.modelCode365=newModelCode
		return item
	}
}
extension Collection{
	func asyncMap<T>(
		_ transform: (Element) async throws -> T
	) async rethrows -> [T] {
		var values = [T]()

		for element in self {
			try await values.append(transform(element))
		}

		return values
	}

}
let encoder = JSONEncoder()
func printJSONDict<T: Encodable>(_ thing: T)throws{
	let data  = try encoder.encode(thing)
	if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]{
		printJSONDict(dict: dict)
	}
}
func printJSONDict(dict sourceDict: [String: Any], withPrefix: String? = nil){
	func printDict(prefix: String, dict: [String: Any]){
		let newPrefix = prefix+"\t"
		for (k,v) in dict{
			print(prefix+k)
			if let newDicts = v as? [[String: Any]]{
				newDicts.forEach{
					printDict(prefix: newPrefix, dict: $0)
					print(newPrefix+"----------------")
				}
			}else if let newDict = v as? [String: Any]{
				printDict(prefix: newPrefix, dict: newDict)
			}else{
				if let array = v as? Array<Any>{
					if let stringArray = array as? Array<String>{
						stringArray.forEach{print(newPrefix+$0)}
					}else{
						array.forEach{print(newPrefix+"\($0)")}
					}
				}else{
					let stringValue: String
					if let asString = v as? String{
						stringValue=asString
					}else{
						stringValue="\(v)"
					}
					print(newPrefix+stringValue)
				}
			}
		}
	}
	printDict(prefix: withPrefix ?? "\t", dict: sourceDict)
}

