//
//  File.swift
//  
//
//  Created by Andreas Loizides on 05/12/2022.
//

import Foundation
import ShopifyKit
import PowersoftKit
extension SHProduct{
	init (from ps: PSItem){
		let variant = SHVariant(from: ps)
		let options = SHOption.makeOptions(fromItems: [ps])
		self.init(id: nil, title: ps.computeModelTitle(), bodyHTML: ps.computeSHDescription(), vendor: ps.getVendor(), productType: ps.getProductType(), createdAt: nil, handle: ps.getShHandle(), updatedAt: nil, publishedAt: nil, templateSuffix: nil, publishedScope: "web", tags: ps.computeSHTag(), adminGraphqlAPIID: nil, variants: [variant], options: options, images: nil, image: nil)
	}
	func variantThatHas(inventory: InventoryLevel)->SHVariant?{
		return variants.first(where: {$0.inventoryItemID == inventory.inventoryItemID})
	}
	func appropriateStocks(from: [Int: InventoryLevel])->[InventoryLevel]{
		return variants.compactMap(\.inventoryItemID).compactMap{invItemID in
			from[invItemID]
		}
	}
	func appropriateStocks(from: [InventoryLevel])->[InventoryLevel]{
		return variants.compactMap(\.inventoryItemID).compactMap{invItemID in
			from.first(where: {$0.inventoryItemID == invItemID})
		}
	}
}
extension Collection where Element==SHProduct{
	
	func variantThatHas(inventory: InventoryLevel)->SHVariant?{
		for product in self{
			if let variant = product.variantThatHas(inventory: inventory){
				return variant
			}
		}
		return nil
	}
}
