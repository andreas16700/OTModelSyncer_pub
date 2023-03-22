//
//  SISModels.swift
//  
//
//  Created by Andreas Loizides on 20/07/2022.
//

import Foundation
import PowersoftKit
import ShopifyKit
public struct SingleModelSync: Codable, Hashable{
	public var id: String
	public var source: ModelAssociatedSourceData
	public var metadata = Metadata()
	public var updates: ConstructedUpdates?
	
	mutating func syncFailed(with error: Error, storeError: Bool = true){
		if storeError{addError(error)}
		self.metadata.ended = .init()
	}
	mutating func addError(_ e: Error){
		guard let errorSyncing = e as? ErrorSyncing else{
			guard let sisError = e as? ErrorType else{
				let unknownError = "\(e)"
				if metadata.unknownErrors == nil {metadata.unknownErrors = [String]()}
				metadata.unknownErrors!.append(unknownError)
				return
			}
			if metadata.errors == nil {metadata.errors = [ErrorType]()}
			metadata.errors!.append(sisError)
			return
		}
		if metadata.syncErrors == nil {metadata.syncErrors = [ErrorSyncing]()}

		metadata.syncErrors!.append(errorSyncing)
	}
	mutating func getModel()throws->[PSItem]{
		guard let model = source.modelItems?.compactMapValues({$0.psItem}) else {
			let error = ErrorType.emptyModel
			addError(error)
			throw error
		}
		
		return Array(model.values)
	}
	
	mutating func hasProductUpdate()throws -> SHProductUpdate?{
		guard let product = source.product else {throw ErrorType.associatedProductNotFound}
		let model = try getModel()
		if let update = try storeErrorAndRethrow({try model.hasProductUpdate(current: product)}){
			return update
		}else{
			return nil
		}
	}
	mutating func hasNewProductUpdate() throws ->SHProduct?{
		guard self.source.product == nil else{return nil}
		let model = try getModel()
		let product = try storeErrorAndRethrow{ try model.getAsNewProduct()}
		
		if updates == nil {updates = .init()}
		updates!.newProduct = product
		return product
	}
	mutating func failedUploadingProduct(_ e: Error){
		addError(e)
		metadata.states[.product] = .failed
	}
	mutating func productSyncDone(){
		metadata.states[.product] = .done
	}
	mutating func variantsSyncDone(){
		metadata.states[.item] = .done
	}
	mutating func inventorySyncDone(){
		metadata.states[.inventory] = .done
	}
	mutating func successfullyUpdatedProduct(_ p: SHProduct){
		metadata.states[.product] = .done
		source.product = p
		for variant in p.variants{
			source.addVariant(variant)
		}
	}
	mutating private func storeModification<T>(itemCode: String, e: T, kp: WritableKeyPath<ConstructedUpdates,Optional<T>>){
		if self.updates == nil {self.updates = .init()}
		self.updates![keyPath: kp] = e
	}
	mutating private func storeModification<T>(itemCode: String, e: T, kp: WritableKeyPath<ConstructedUpdates,Optional<Dictionary<String,T>>>){
		if self.updates == nil {self.updates = .init()}
		if self.updates![keyPath: kp] == nil {self.updates![keyPath: kp] = .init()}
		self.updates![keyPath: kp]![itemCode] = e
	}
	mutating func hasVariantUpdates()throws->VariantsUpdates?{
		guard let _ = try? getModel() else{
			try storeAndThrowError(.emptyModel);fatalError()
		}
		guard let modelAndAssociated = source.modelItems else {try storeAndThrowError(.noAssociatedItemData);fatalError()}
		var updates = VariantsUpdates()
		for (_, associated) in modelAndAssociated{
			let item = associated.psItem!
			if let currentVariant = associated.variant{
				let update = try storeErrorAndRethrow {try item.hasVariantUpdate(currentVariant: currentVariant, updateOptions: true)}
				if let update = update{
					storeModification(itemCode: item.itemCode365, e: update, kp: \.variantUpdateByItemCode)
					updates.updates.append(update)
				}
			}else{
				let newVariant = item.asNewVariant()
				storeModification(itemCode: item.itemCode365, e: newVariant, kp: \.newVariantByItemCode)
				updates.newEntries.append(newVariant)
			}
		}
		if updates.isEmpty{
			return nil
		}else{
			return updates
		}
	}
	mutating func failedVariantsSync(_ e: Error){
		addError(e)
		metadata.states[.item] = .failed
	}
	public func getItem(code: String)->PSItem?{
		return self.source.modelItems?[code]?.psItem
	}
	mutating func storeAssociated<T>(itemCode: String, thing: T, kp: WritableKeyPath<ModelAssociatedSourceData.ItemAssociatedData,Optional<T>>)throws{
		if self.source.modelItems == nil {self.source.modelItems = .init()}
		source.modelItems![itemCode, default: .init()][keyPath: kp] = thing
	}
	mutating func successUpdatedVariant(_ updated: SHVariant){
		let itemCode = updated.sku
		try! storeAssociated(itemCode: itemCode, thing: updated, kp: \.variant)
		if let varID = updated.id{
			if let varIndex = source.product?.variants.firstIndex(where: {$0.id == varID}){
				source.product!.variants[varIndex]=updated
			}else{
				source.product!.variants.append(updated)
			}
		}
	}
	mutating func hasInventoryUpdates()throws->[String: SHInventorySet]?{
		guard let modelsDict = self.source.modelItems else {try storeAndThrowError(.modelNotFound); fatalError()}
		var theUpdates = [String: SHInventorySet]()
		for (itemCode, associated) in modelsDict{
			guard let psStock = associated.psStock else{
				try storeAndThrowError(.psStockNotFound);fatalError()
			}
			guard let shStock = associated.shStock else{
				try storeAndThrowError(.shInvNotFound);fatalError()
			}
			if let theresAnUpdate = psStock.hasUpdate(current: shStock){
				theUpdates[itemCode]=theresAnUpdate
				var genuineUpdate = true
				//Is this (1) an update on an existing variant or (2) is this just the initial setting of the inventory?
				//If this sync is about a new product then this should be noted as just the initial (case 1).
				if self.updates?.newProduct != nil{
					genuineUpdate = false
				}
				//If this is for a new variant this is also the case (case 1)
				if let newVariants =  self.updates?.newVariantByItemCode?.keys, newVariants.contains(itemCode){
					genuineUpdate = false
				}
				//Otherwise this should be noted as a genuine inventory update (case 2)
				storeModification(itemCode: itemCode, e: theresAnUpdate, kp: genuineUpdate ? \.inventoryUpdateByItemCode : \.newInventoryByItemCode)
				if genuineUpdate{
					try storeAssociated(itemCode: itemCode, thing: shStock, kp: \.shStockBeforeΜοdification)
				}
			}
		}
		return theUpdates.isEmpty ? nil : theUpdates
	}
	mutating func updatedInventory(itemCode: String, updated: InventoryLevel){
		try! storeAssociated(itemCode: itemCode, thing: updated, kp: \.shStock)
	}
	mutating func inventoryUpdateFailed(forItem: String){
		metadata.states[.inventory] = .failed
	}
}
