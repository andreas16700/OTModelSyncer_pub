//
//  Syncing.swift
//  
//
//  Created by Andreas Loizides on 18/09/2022.
//

import Foundation

import PowersoftKit
import ShopifyKit

public actor SingleModelSyncer{
	typealias EndState = SingleModelSync.EndState
	typealias ErrorType = SingleModelSync.ErrorType
	typealias SyncKind = SingleModelSync.SyncKind
	
	let ps: PowersoftClientProtocol
	let sh: ShopifyClientProtocol
	let shouldFetchPSData: Bool
	let shouldFetchShData: Bool
	let saveMethod: ((SingleModelSync)async->Bool)?
	
	let syncID: String
	
	
	public nonisolated func getSyncID()->String{syncID}
	public init(modelCode: String
				,ps: PowersoftClientProtocol
				,sh: ShopifyClientProtocol
				,psDataToUse: ([PSItem], [PSListStockStoresItem])? = nil
				,shDataToUse: (SHProduct, [InventoryLevel])? = nil
				,saveMethod: ((SingleModelSync)async->Bool)? = nil){
		self.modelCode = modelCode
		self.syncID = UUID().uuidString
		var data: SingleModelSync = .init(id: syncID, source: .init(modelCode: modelCode))
		self.ps=ps
		self.sh=sh
		self.saveMethod=saveMethod
		if let psDataToUse{
			data.source.addItems(items: psDataToUse.0)
			for stock in psDataToUse.1 {
				data.source.addPSStock(itemCode: stock.itemCode365, stock)
			}
			self.shouldFetchPSData=false
		}else{
			self.shouldFetchPSData=true
		}
		if let shDataToUse{
			let product = shDataToUse.0
			data.source.addProduct(product)
			for inventory in shDataToUse.1{
				if let variant = product.variantThatHas(inventory: inventory){
					data.source.addShInventory(itemCode: variant.sku, inventory)
				}
			}
			self.shouldFetchShData=false
		}else{
			self.shouldFetchShData=true
		}
		self.data=data
	}
	public var modelCode: String

	public private(set) var data: SingleModelSync{
		didSet{
			data.metadata.lastUpdated = Date()
		}
	}
	
	private func addError(_ e: Error){data.addError(e)}
	private func catchByStoringError<T>(_ op: () async throws->T?)async->T?{
		do{
			return try await op()
		}catch{
			addError(error)
			return nil
		}
	}
	private func catchByStoringError<T>(_ op: () async throws->T)async->T?{
		do{
			return try await op()
		}catch{
			addError(error)
			return nil
		}
	}
	private func syncDone(){
		data.metadata.ended = Date()
	}
	private func syncFailed(with error: Error, storeError: Bool = true){
		Task{await saveSync()}
		data.metadata.ended = Date()
		self.data.syncFailed(with: error)
	}
	public func sync(savePeriodically: Bool = true)async->SingleModelSync?{
		Task{await saveSync()}
		printDiag("Syncing "+modelCode)
		guard !data.metadata.inProgress else {
			printDiag("Already in progress.")
			return nil
		}
		
		if self.shouldFetchPSData{
			printDiag("fetching source PS data..")
			guard await getPSData() else{return data}
		}
		if savePeriodically{Task{await saveSync()}}
		let anItemsData = data.source.modelItems!.first!.value
		
		
		if self.shouldFetchShData{
			printDiag("fetching source Shopify data..")
			await getSHProductAndVariants(item: anItemsData.psItem!)
		}
		if savePeriodically{Task{await saveSync()}}
		
		printDiag("Initiating product-level sync..")
		data.metadata.states[.product] = .waiting
		guard await productSync() else{return data}
		if savePeriodically{Task{await saveSync()}}
		
		printDiag("Initiating item-level sync..")
		data.metadata.states[.item] = .waiting
		guard await variantsSync() else{return data}
		if savePeriodically{Task{await saveSync()}}
		
		printDiag("Initiating inventory sync..")
		data.metadata.states[.inventory] = .waiting
		guard await getShInventoryData() else{return data}
		if savePeriodically{Task{await saveSync()}}
		guard await inventorySync() else{return data}
		
		printDiag("sync is done")
		syncDone()
		printDiag("returning")
		await saveSync()
		return data
	}
	private func getPSData()async ->Bool{
		let subject = "On (single model syncer) syncing model \(modelCode). "
		log(subject)
		guard let model = await ps.getModel(modelCode: modelCode) else{
			print("Model \(modelCode) could not be fetched.")
			let error = ErrorType.modelNotFound
			syncFailed(with: error)
			return false
		}
		print("Fetched model \(modelCode) with \(model.count) items.")
		self.data.source.addItems(items: model)
		for itemCode in model.map(\.itemCode365){
			if let psStock = await ps.getStock(for: itemCode){
				print("Fetched stock for item \(itemCode).")
				self.data.source.addPSStock(itemCode: itemCode, psStock)
			}else{
				print("Stock for item \(itemCode) could not be fetched.")
				let error = ErrorType.psStockNotFound
				syncFailed(with: error)
				return false
			}
		}
		return true
	}
	private func getSHProductAndVariants(item: PSItem)async{
		let handle = item.getShHandle()
		guard let product = await sh.getProduct(withHandle: handle) else{
			print("No product exists for model. Will create.")
			return
		}
		print("Product for model exists and has id \(product.id!) and \(product.variants.count) variants.")
		self.data.source.productBeforeModifications=product
		self.data.source.addProduct(product)
		return
	}
	private func productSync()async ->Bool{
		do{
			if let newProduct = try data.hasNewProductUpdate(){
				print("Creating new product for model with handle \(newProduct.handle) and \(newProduct.variants.count) variants")
				guard let uploaded = await sh.createNewProduct(new: newProduct) else{
					print("Could not publish product \(newProduct.handle).")
					let error = ErrorType.newProductWasNotAcceptedByShopify
					data.failedUploadingProduct(error)
					syncFailed(with: error, storeError: false)
					return false
				}
				data.successfullyUpdatedProduct(uploaded)
			}else{
				if let productUpdate = try data.hasProductUpdate(){
					print("Product has an update.")
					guard let uploaded = await sh.updateProduct(with: productUpdate) else{
						print("Could not publish update for product.")
						let error = ErrorType.productUpdateWasNotAcceptedByShopify
						data.failedUploadingProduct(error)
						syncFailed(with: error, storeError: false)
						return false
					}
					data.successfullyUpdatedProduct(uploaded)
				}else{
					print("Product is up to update.")
					data.productSyncDone()
				}
			}
		}catch{
			print("Error constructing product updates: \(error)")
			data.failedUploadingProduct(error)
			syncFailed(with: error, storeError: false)
			return false
		}
		return true
	}
	private func variantsSync()async->Bool{
		do{
			guard let productID = data.source.product?.id else{
				print("Could not find ID of product in order to update its variants")
				let e = ErrorType.associatedProductNotFound
				data.failedVariantsSync(e)
				syncFailed(with: e, storeError: false)
				return false
			}
			guard let updates = try data.hasVariantUpdates() else{
				print("Variants are up to date.")
				data.variantsSyncDone();return true
			}
			for newVariant in updates.newEntries{
				print("New variant \(newVariant.sku!) found.")
				if let created = await sh.createNewVariant(variant: newVariant, for: productID){
					print("Created variant \(newVariant.sku!) with id \(created.id!)")
					data.successUpdatedVariant(created)
				}else{
					print("Unable to publish new variant \(newVariant.sku!)")
					let error: ErrorType = .variantUpdateError
					data.failedVariantsSync(error)
					syncFailed(with: error, storeError: false)
				}
			}
			for varUpdate in updates.updates{
				print("Update for variant \(varUpdate.id!) found.")
				if let updated = await sh.updateVariant(with: varUpdate){
					print("Updated variant \(updated.id!) with sku \(updated.sku).")
					data.successUpdatedVariant(updated)
				}else{
					print("Unable to publish update for variant \(varUpdate.id!).")
					let e = ErrorType.variantUpdateWasNotAcceptedByShopify
					data.failedVariantsSync(e)
					syncFailed(with: e, storeError: false)
					return false
				}
			}
		}catch{
			data.failedVariantsSync(error)
			syncFailed(with: error, storeError: false)
			return false
		}
		data.variantsSyncDone()
		return true
	}

	private func getShInventoryData()async ->Bool{
		guard let dict = data.source.modelItems else {
			let e = ErrorType.noAssociatedItemData
			syncFailed(with: e)
			return false
		}
		defer{
			for (item, ass) in data.source.modelItems!{
				if let _ = ass.shStock{
//					print(item+": "+"\(inv.available!)")
				}else{
					print(item+": nope! but has psStock? \(ass.psStock == nil ? "nope!" : "yea")")
				}
			}
		}
		var inventoryIDsToFetch = [(String,Int)]()
		for (item, ass) in dict{
			guard let variant = ass.variant else{
				let e = ErrorType.associatedVariantNotFound
				syncFailed(with: e)
				return false
			}
			guard let invID = variant.inventoryItemID else{
				let e = ErrorType.variantHasNoInvID
				syncFailed(with: e)
				return false
			}
			if let existingShStock = ass.shStock, existingShStock.inventoryItemID==invID{
				//no need to fetch inventory
				continue
			}
			inventoryIDsToFetch.append((item, invID))
		}
		let itemCodes = inventoryIDsToFetch.map(\.0)
		let ids = inventoryIDsToFetch.map(\.1)
		guard let i = await sh.getInventories(of: ids) else{
			let e = ErrorType.couldNotFetchShInv
			syncFailed(with: e)
			return false
		}
		guard ids.count == i.count else {
			let e = ErrorType.couldNotFetchShInv
			syncFailed(with: e)
			printDiag("Requested inventories of \(ids.count) items but only got \(i.count)!")
			return false
		}
		log("Adding inventories for \(ids.count) items..")
		data.updatedInventories(itemCodes: itemCodes, updated: i)
		return true
	}
	private func inventorySync()async ->Bool{
		do{
			guard let updates = try data.hasInventoryUpdates() else{
				print("Inventories up to date.")
				self.data.inventorySyncDone()
				return true
			}
			for (itemCode, update) in updates{
				print("Should update stock of "+itemCode+" to -> \(update.available)")
				guard let associated = data.source.getItemAssociatedData(itemCode: itemCode), let currentInventory = associated.shStock else{
					print(itemCode+" has no associated data!")
					let e = ErrorType.noAssociatedItemData
					syncFailed(with: e)
					return false
				}
				
				guard let u = await sh.updateInventory(current: currentInventory, update: update) else{
					print(itemCode+"'s stock was not updated!")
					let e = ErrorType.couldNotUpdateShInv
					syncFailed(with: e)
					return false
				}
				let currentStr = currentInventory.available == nil ? "_" : "\(currentInventory.available!)"
				print("stock of "+itemCode+" was updated: \(currentStr)  -> \(update.available)")
				data.updatedInventory(itemCode: itemCode, updated: u)
			}
			data.inventorySyncDone()
			return true
		}catch{
			print("Error constructing inventory updates: \(error)")
			syncFailed(with: error)
			return false
		}
	}
	private func saveSync()async{
		guard let saveMethod else{return}
		let wasSaved = await saveMethod(data)
		if wasSaved{
			print("Saved.")
		}else{
			print("Error saving sync!")
		}
	}
}
extension PSListStockStoresItem{
	func hasUpdate(current: InventoryLevel)->SHInventorySet?{
		let newListingCount = stock < 0 ? 0 : stock
		guard current.available != newListingCount else{return nil}
		return SHInventorySet(locationID: current.locationID, inventoryItemID: current.inventoryItemID, available: newListingCount)
	}
}
