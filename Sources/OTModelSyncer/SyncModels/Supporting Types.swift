//
//  File.swift
//  
//
//  Created by Andreas Loizides on 10/10/2022.
//

import Foundation
import ShopifyKit
import PowersoftKit
extension SingleModelSync{
	public enum EndState: String, Error, Codable, Hashable{
		case created, waiting, done, failed, incomplete
	}
	public enum SyncKind: String, Codable, Hashable{
		case item, inventory, product
	}
	public enum ErrorType: String, Error, Codable, Hashable{
		case itemNotFound, modelNotFound, associatedProductNotFound, associatedVariantNotFound, moreThanOneProductFound, moreThanOneVariantFound, psStockNotFound, shInvNotFound, couldNotConstructUpdate, hustonWeHaveAProblem, emptyModel, noAssociatedItemData, variantUpdateError, couldNotFetchShInv, couldNotUpdateShInv, variantHasNoInvID, newProductWasNotAcceptedByShopify, productUpdateWasNotAcceptedByShopify, newVariantWasNotAcceptedByShopify, variantUpdateWasNotAcceptedByShopify
	}
	public struct VariantsUpdates: Codable, Hashable{
		var updates = [SHVariantUpdate]()
		var newEntries = [SHVariantUpdate]()
		var isEmpty: Bool {updates.isEmpty && newEntries.isEmpty}
	}
	public struct ModelAssociatedSourceData:Codable, Hashable{
		public init(modelCode: String, modelItems: [String : SingleModelSync.ModelAssociatedSourceData.ItemAssociatedData]? = nil, product: SHProduct? = nil) {
			self.modelCode = modelCode
			self.modelItems = modelItems
			self.product = product
		}
		public init(modelCode: String, items: [PSItem]){
			self.modelCode=modelCode
			self.modelItems = .init()
		}
		mutating func addItems(items: [PSItem]){
			if modelItems == nil {modelItems = .init()}
			items.forEach{
				modelItems![$0.itemCode365, default: .init()].psItem=$0
			}
		}
		public func getItem(code: String)->PSItem?{
			return modelItems?[code]?.psItem
		}
		public func getItemAssociatedData(itemCode: String)->ModelAssociatedSourceData.ItemAssociatedData?{
			return modelItems?[itemCode]
		}
		mutating func addProduct(_ p: SHProduct){
			self.product=p
			p.variants.forEach{addVariant($0)}
		}
		mutating func addVariant(_ v: SHVariant){
			let itemCode = v.sku
			self.modelItems![itemCode, default: .init()].variant=v
		}
		mutating func addPSStock(itemCode: String, _ s: PSListStockStoresItem){
			self.modelItems![itemCode, default: .init()].psStock = s
		}
		mutating func addShInventory(itemCode: String, _ i: InventoryLevel){
			self.modelItems![itemCode, default: .init()].shStock = i
		}
		public struct ItemAssociatedData: Codable, Hashable{
			var psStock: PSListStockStoresItem?
			var shStock: InventoryLevel?
			var variant: SHVariant?
			var shStockBeforeΜοdification: InventoryLevel?
			var psItem: PSItem?
			var enoughToSyncInventory: Bool{psStock != nil && shStock != nil}
			var enoughtToSyncItem: Bool{variant != nil && psItem != nil}
		}
		public let modelCode: String
		public var modelItems: [String: ItemAssociatedData]?
		public var productBeforeModifications: SHProduct?
		public var product: SHProduct?
	}
	public struct Metadata: Codable, Hashable{
		
		private var startedDateString: String?
		public var started: Date? {get{Date.fromString(string: startedDateString)}set{startedDateString = newValue?.toString()}}
		private var endedDateString: String?
		public var ended: Date? {get{Date.fromString(string: endedDateString)}set{endedDateString = newValue?.toString()}}
		
		public var errors: [ErrorType]?
		public var syncErrors: [ErrorSyncing]?
		public var unknownErrors: [String]?
		private var lastUpdatedDateString: String = Date().toString()
		public var lastUpdated: Date {get{Date.fromString(string: lastUpdatedDateString)!}set{lastUpdatedDateString = newValue.toString()}}
		public var states: [SyncKind:EndState] = [
			.product : .created,
			.item : .created,
			.inventory : .created
		]
		public var inProgress: Bool {states.contains(where: {$0.value == .waiting})}
	}
	public struct ConstructedUpdates: Codable, Hashable{
		public var variantUpdateByItemCode: [String: SHVariantUpdate]?
		public var productUpdate: SHProductUpdate?
		public var inventoryUpdateByItemCode: [String: SHInventorySet]?
		public var newVariantByItemCode: [String: SHVariantUpdate]?
		public var newProduct: SHProduct?
		public var newInventoryByItemCode: [String: SHInventorySet]?
	}
}
