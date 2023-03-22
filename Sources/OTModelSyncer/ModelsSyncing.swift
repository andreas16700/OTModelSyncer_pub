//
//  File.swift
//  
//
//  Created by Andreas Loizides on 10/12/2022.
//

import Foundation

import PowersoftKit
import ShopifyKit

public actor ModelsSyncer{
	let psClient: PowersoftClientProtocol
	let shClient: ShopifyClientProtocol
	let individualSyncSaveMethod: ((SingleModelSync)async->Bool)?
	let saveMethod: ((ModelsSync)async->Bool)?
	typealias PSModelType = [PSItem]
	typealias SourceData = ([PSModelType],[PSListStockStoresItem],[SHProduct],[InventoryLevel])
	var sync: ModelsSync
	var isIncomplete = false
	var syncers = [String: SingleModelSyncer]()
	public init(
		 ps: PowersoftClientProtocol
		 ,sh: ShopifyClientProtocol
		 ,individualSyncSaveMethod: ((SingleModelSync)async->Bool)? = nil
		 ,saveMethod: ((ModelsSync)async->Bool)? = nil){
		
		self.sync = .init()
		self.shClient=sh
		self.psClient=ps
		self.individualSyncSaveMethod=individualSyncSaveMethod
		self.saveMethod=saveMethod
	}
	
	private func fetchSourceData()async->SourceData?{
		
		
		async let psItems = psClient.getAllItems(type: .eCommerceOnly)
		async let shProds = shClient.getAllProducts()
		async let psStocks = psClient.getAllStocks(type: .eCommerceOnly)
		async let shStocks = shClient.getAllInventories()
		guard
		let psItems = await psItems,
		let psStocks = await psStocks,
		let shProds = await shProds,
		let shStocks = await shStocks
		else{
			print("[ERROR] failed to fetch source data!")
			return nil
		}
		let models = Dictionary(grouping: psItems, by: {($0.modelCode365 == "") ? $0.getShHandle() : $0.modelCode365}).values
		return (Array(models), psStocks,shProds,shStocks)
	}
	
	private func makeSyncers(data: SourceData)async ->[String: SingleModelSyncer]{
		async let prodsA = data.2.toDictionary(usingKP: \.handle)
		async let shStockByInvIDA = data.3.toDictionary(usingKP: \.inventoryItemID)
		async let psStocksByModelCodeA = data.1.toDictionaryArray(usingKP: \.modelCode365)
		let models = data.0
		let prods = await prodsA
		let shStockByInvID = await shStockByInvIDA
		let psStocksByModelCode = await psStocksByModelCodeA
		return models.reduce(into: [String: SingleModelSyncer](minimumCapacity: models.count)){dic, model in
			let refItem = model.first!
			let modelCode = refItem.modelCode365
			let stocks = psStocksByModelCode[modelCode] ?? []
			
			let product = prods[refItem.getShHandle()]
			let shStocks = product?.appropriateStocks(from: shStockByInvID)
			let shData = product == nil ? nil : (product!,shStocks!)
			let syncer: SingleModelSyncer = .init(modelCode: modelCode, ps: psClient, sh: shClient, psDataToUse: (model,stocks), shDataToUse: shData, saveMethod: individualSyncSaveMethod)
			
			sync.addToQueue(modelCode: modelCode, syncID: syncer.getSyncID())
			
			dic[modelCode]=syncer
		}
	}
//	private func makeSyncers(data: SourceData)->[String: SingleModelSyncer]{
//		return data.0.reduce(into: [String: SingleModelSyncer]()){dict, model in
//			let referenceItem = model.first!
//			let modelCode = referenceItem.modelCode365
//			let product = data.2.first(where: {$0.handle == referenceItem.getShHandle()})
//			let shStocks = product?.appropriateStocks(from: data.3)
//			let stocks = data.1.filter{$0.modelCode365==modelCode}
//			let shData = product == nil ? nil : (product!,shStocks!)
//			let syncer: SingleModelSyncer = .init(modelCode: modelCode, ps: psClient, sh: shClient, psDataToUse: (model,stocks), shDataToUse: shData, saveMethod: individualSyncSaveMethod)
//			sync.addToQueue(modelCode: modelCode, syncID: syncer.getSyncID())
//			dict[modelCode]=syncer
//		}
//	}
	private func save(){
		if let saveMethod{
			Task{
				let _ = await saveMethod(sync)
			}
		}
	}
	private func syncDone(modelCode: String, sync theSync: SingleModelSync){
		self.sync.doneSync(modelCode: modelCode, sync: theSync)
	}
	private func syncFailed(modelCode: String, syncID: String){
		self.sync.failedSync(modelCode: modelCode, syncID: syncID)
	}
	
	private func markIsIncomplete(){
		self.isIncomplete=true
	}
	public func sync()async->ModelsSync?{
		guard !sync.isInProgress else {print("Sync already in progres");return nil}
		sync.syncInitiated()
		guard let data = await fetchSourceData() else{
			let reason = "Failed to fetch source data"
			sync.failed(reason: reason);return nil
		}
		let syncers = await makeSyncers(data: data)
		sync.syncIDByModelCode = await withTaskGroup(of: (String, String).self, returning: [String: String].self){group in
			for syncer in syncers.values{
				group.addTask{
					let modelCode = await syncer.modelCode
					let syncID = syncer.syncID
					return (modelCode,syncID)
				}
			}
			return await group.reduce(into: .init(minimumCapacity: syncers.count)){
				$0[$1.0]=$1.1
			}
		}
		await withTaskGroup(of: SingleModelSync?.self){group in
			for (modelCode, syncer) in syncers{
				group.addTask{await syncer.sync()}
				for await someSync in group{
					if let modelSync = someSync{
						syncDone(modelCode: modelCode, sync: modelSync)
					}else{
						self.markIsIncomplete()
						syncFailed(modelCode: modelCode, syncID: syncer.getSyncID())
					}
				}
				save()
				printState()
			}
		}
		sync.done(isIncomplete: self.isIncomplete)
		return sync
	}
	public func getPercentDone()->Double{
		sync.percentDone
	}
	
	public func printState(){
		let doneString = String(format: "%.2f", sync.percentDone)
		print("[STATUS] \(doneString)% done: \(sync.interestingDoneSyncs?.count ?? 0) with updates done, \(sync.uninterestingDoneSyncs?.count ?? 0) with no updates needed done, \(sync.failedSyncs?.count ?? 0) failed, \(sync.inQueueSyncs?.count ?? 0) remaining.")
	}
}
