//
//  Misc.swift
//  
//
//  Created by Andreas Loizides on 05/12/2022.
//

import Foundation
import ShopifyKit
import PowersoftKit

let formatter = ISO8601DateFormatter()
extension Date{
	static func fromString(string: String?)->Date?{
		guard let string = string else {return nil}
		return formatter.date(from: string)
	}
	static func fromString(string: String)->Date?{
		return formatter.date(from: string)
	}
	func toString()->String{
		return formatter.string(from: self)
	}
	func toGreekString()->String{
		let df = DateFormatter()
		df.locale = Locale.init(identifier: "el-CY")
		df.dateStyle = .long
		return df.string(from: self)
	}
}

func getByModel(allPSItems: [PSItem])->[String: [PSItem]]{
	var result = [String: [PSItem]]()
	for i in 0..<allPSItems.count{
		let item = allPSItems[i]
		let model = item.modelCode365
		let code = item.itemCode365
		var productName = model
		if model == ""{
			 productName=code
		}
		if result[productName] == nil{
			result[productName] = [item]
		}else{
			result[productName]!.append(item)
		}
	}
	print("There are \(result.count) unique items")
	return result
}

func createNewShopifyProduct(withVariants psVariants: [PSItem])->SHProduct{
	
	var sizes = [String]()
	var colors = [String]()
	var variants = [SHVariant]()
	
	var title=""
	
	for psVariant in psVariants {
		if !sizes.contains(psVariant.sizeName){
			sizes.append(psVariant.sizeName)
		}
		if !colors.contains(psVariant.colorName){
			colors.append(psVariant.colorName)
		}
		var barcode = ""
		//if a non-label barcode is found, then it is selected.
		for barcodes in psVariant.listItemBarcodes{
			if !barcodes.isLabelBarcode{
				barcode=barcodes.barcode
			}
		}
		//if no non-label barcode is found then the first barcode is selected.
		if barcode==""{barcode=psVariant.listItemBarcodes[0].barcode}
		
		if title == ""{
			if psVariant.itemName != ""{
				title = psVariant.itemName
			}else{
				if psVariant.itemName2 != ""{
					title = psVariant.itemName2
				}else{
					title = psVariant.itemCode365
				}
			}
		}
		
		
		var noColor=false
		var noSize=false
		if psVariant.colorName==""{
			noColor=true
		}
		if psVariant.sizeName==""{
			noSize=true
		}
		
		variants.append(SHVariant(id: nil, productID: nil, title: title, price: "\(psVariant.priceIncl1)", sku: psVariant.itemCode365, position: nil, inventoryPolicy: .deny, compareAtPrice: nil, fulfillmentService: .manual, inventoryManagement: .shopify, option1: noSize ? nil : psVariant.sizeName, option2: noColor ? nil : psVariant.colorName, option3: nil, createdAt: nil, updatedAt: nil, taxable: true, barcode: barcode, grams: Int(psVariant.itemWeight), imageID: nil, weight: Double(psVariant.itemWeight), weightUnit: .kg, inventoryItemID: nil, inventoryQuantity: nil, oldInventoryQuantity: nil, requiresShipping: true, adminGraphqlAPIID: nil))
	}
	
	
	let tags = "Gender:\(psVariants[0].attribute1_Name), Rebound:\(psVariants[0].attribute3_Name), Season:'\(psVariants[0].seasonName), Style:\(psVariants[0].attribute2_Name)"
	
	var handle = ""
	if psVariants[0].modelCode365==""{
		handle=psVariants[0].itemCode365
	}else{
		handle=psVariants[0].modelCode365
	}
	var options = [SHOption]()
	if sizes.count != 0 && !(sizes.count==1 && sizes[0] == ""){
		options.append(SHOption(id: nil, productID: nil, name: "Size", position: nil, values: sizes))
	}
	if colors.count != 0 && !(colors.count==1 && colors[0] == ""){
		options.append(SHOption(id: nil, productID: nil, name: "Color", position: nil, values: colors))
	}
	let product = SHProduct(id: nil, title: title, bodyHTML: psVariants[0].specifications, vendor: psVariants[0].brandName, productType: psVariants[0].categoryName, createdAt: nil, handle: handle, updatedAt: nil, publishedAt: nil, templateSuffix: nil, publishedScope: "web", tags: tags, adminGraphqlAPIID: nil, variants: variants, options: options.count==0 ? nil : options, images: nil, image: nil)
	
	return product
}
