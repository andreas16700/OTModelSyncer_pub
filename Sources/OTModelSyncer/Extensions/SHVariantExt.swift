//
//  File.swift
//  
//
//  Created by Andreas Loizides on 05/12/2022.
//

import Foundation
import ShopifyKit
import PowersoftKit
extension SHVariant{
	init(from ps: PSItem){
		var comparePriceString: String?
		if let compD = ps.computeSHComparePrice(){
			comparePriceString="\(compD)"
		}
		let barcode = ps.listItemBarcodes.first(where: {!$0.isLabelBarcode})?.barcode
		self.init(id: nil, productID: nil, title: ps.computeSHVariantTitle(), price: "\(ps.computeSHPrice())", sku: ps.itemCode365, position: nil, inventoryPolicy: .deny, compareAtPrice: comparePriceString, fulfillmentService: .manual, inventoryManagement: .shopify, option1: ps.getOption1(name: false), option2: ps.getOption2(name: false), option3: ps.getOption3(name: false), createdAt: nil, updatedAt: nil, taxable: true, barcode: barcode, grams: 0, imageID: nil, weight: Double(ps.itemWeight) , weightUnit: .kg, inventoryItemID: nil, inventoryQuantity: nil, oldInventoryQuantity: nil, requiresShipping: true, adminGraphqlAPIID: nil)
	}
}
