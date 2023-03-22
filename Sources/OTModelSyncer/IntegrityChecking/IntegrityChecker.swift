//
//  File.swift
//  
//
//  Created by Andreas Loizides on 10/08/2021.
//

import Foundation
import ShopifyKit
import PowersoftKit

protocol ConcatinableAsString{
    func asString()->String
}
extension Array{
	mutating func optionalAppend(_ a: Self?){
		if let a=a{append(contentsOf: a)}
	}
}
extension SHOption: ConcatinableAsString{
    func asString() -> String {
        return "Name: \(self.name) Values: \(self.values.joined(separator: ", "))"
    }
}
extension PSOption: ConcatinableAsString{
    func asString() -> String {
        return "Name:\(self.name) Value:\(self.value)"
    }
}
extension Array: ConcatinableAsString where Element == PSOption{
    func asString() -> String {
        return self.map{$0.asString()}.joined(separator: ", ")
    }
}
protocol IntegrityChecker{
    var errors: [String]    {get set}
    mutating func somethingIsWrong()->[String]?
}
extension IntegrityChecker{
    mutating func addMismatch(_ name: String, item: String, shopify: String){
        errors.append("\(name) mismatch. Item's: \(item) but on shopify it's \(shopify)")
    }
}
public struct IntegrityCheckerModelProduct: IntegrityChecker{
	init(errors: [String] = [String](), model: [PSItem], product: SHProduct) {
		self.errors = errors
		self.model = model
		self.product = product
		itemCheckers = .init()
		model.forEach{item in
			if let variant = product.variants.first(where: {$0.sku.lowercased() == item.itemCode365.lowercased()}){
				itemCheckers[item.itemCode365] = .init(itemProduct: .init(item: item, product: product), itemVariant: .init(item: item, variant: variant))
			}else{
				self.errors.append("No variant for item "+item.itemCode365)
			}
				
			}
	}
	
	var errors = [String]()
	let model: [PSItem]
	let product: SHProduct
	var itemCheckers: [String: ItemCheckers?]
	
	public struct ItemCheckers{
		let itemProduct: IntegrityCheckerItemProduct
		let itemVariant: IntegrityCheckerItemVariant
		var errors: [String]?{
			var e = [String]()
			var v = itemVariant
			var p = itemProduct
			e.optionalAppend(p.somethingIsWrong())
			e.optionalAppend(v.somethingIsWrong())
			return e.isEmpty ? nil : e
		}
	}
	
	mutating func somethingIsWrong() -> [String]? {
		let checkerErrors = itemCheckers.reduce(into: [String]()){arr, entry in
			arr.optionalAppend(entry.value?.errors)
		}
		let result = errors + checkerErrors
		return result.isEmpty ? nil : result
	}
	
	
}
public struct IntegrityCheckerItemProduct: IntegrityChecker{
    
    let item: PSItem
    let product: SHProduct
    
    var errors = [String]()
    
    mutating func matchesExcactlyOneVariantFromProduct()->Bool{
        var match: SHVariant?
        for variant in product.variants{
            if variant.sku == item.itemCode365{
                guard match == nil else{
                    addMismatch("More than one variant for an item", item: item.itemCode365, shopify: match!.sku + " and " + variant.sku)
                    return false
                }
                match = variant
            }
        }
        return true
    }
    mutating func matchesProductOptions()->Bool{
        let options = item.getOptions()
        guard let prodOptions = product.options else{
            addMismatch("No options for product", item: item.itemCode365, shopify: "None")
            return false
        }
        guard prodOptions.count == options.count else{
            addMismatch("Unequal number of options", item: "Item has \(options.count) options: \(options.asString())", shopify: "")
            return false
        }
        for i in 0..<prodOptions.count{
            let prodOption = prodOptions[i]
            let itemOption = options[i]
            guard prodOption.name == itemOption.name
                    && prodOption.values.contains(itemOption.value) else{
                addMismatch("Option mismatch", item: itemOption.asString(), shopify: prodOption.asString())
                return false
            }
        }
        return true
    }
    mutating func matchesTitle()->Bool{
        let itemTitle = item.computeModelTitle()
        let prodTitle = product.title
        if itemTitle == prodTitle{
            return true
        }else{
            addMismatch("Title mismatch", item: itemTitle, shopify: prodTitle)
            return false
        }
    }
    mutating func matchesBodyHTML()->Bool{
        let itemBody = item.computeSHDescription()
        let prodBody = product.bodyHTML
        if let newBody = item.getNewBodyHTML(comparedWith: product){
            addMismatch("HTML Body mismatch. Should be: \(newBody)", item: itemBody, shopify: prodBody ?? "None")
            return false
        }else{
            return true
        }
    }
    mutating func tagsMatch()->Bool{
        if item.getNewTag(comparedWith: product) != nil{
            addMismatch("Tags mismatch", item: item.computeSHTag(), shopify: product.tags)
            return false
        }else{
            return true
        }
    }
    mutating func vendorMatch()->Bool{
        if item.getNewVendor(comparedWith: product) != nil{
            addMismatch("Vendor mismatch", item: item.getVendor(), shopify: product.vendor)
            return false
        }else{
            return true
        }
    }
    mutating func matches()->Bool{
        return
            matchesTitle()
        &&
        matchesProductOptions()
        &&
        matchesBodyHTML()
        &&
        vendorMatch()
        &&
        tagsMatch()
        &&
        matchesExcactlyOneVariantFromProduct()
        
    }
    mutating func somethingIsWrong() -> [String]? {
        if matches(){
            return nil
        }else{
            return errors
        }
    }
}
public struct IntegrityCheckerItemVariant: IntegrityChecker{
    
    let item: PSItem
    let variant: SHVariant
    
    var errors = [String]()
    
    private mutating func reset(){errors = [String]()}
    
    
    mutating func titleMatches()->Bool{
        if let newTitle = item.getNewTitle(comparedWith: variant){
            addMismatch("Title mismatch (should be \(newTitle)", item: item.computeSHVariantTitle(), shopify: variant.title)
            return false
        }else{
            return true
        }
    }
    mutating func priceMatches()->Bool{
        let price = item.computeSHPrice()
        let with = variant.price
        guard let otherAsNumber = Double(with) else{
            addMismatch("Price mismatch (shopify price not a number!)", item: "\(price)", shopify: with)
            return false
        }
        
        var difference = price-otherAsNumber
        if difference<0{difference.negate()}
        let tolerance = 0.1
        let percentAgeOfOriginalValue = (difference*100)/price
        if percentAgeOfOriginalValue<tolerance {
            return true
        }else{
            addMismatch("Price mismatch", item: "\(price)", shopify: "\(otherAsNumber)")
            return false
        }
        
    }
    mutating func comparePriceMatches()->Bool{
        let itemCAP = item.computeSHComparePrice()
        let variantCAP = variant.compareAtPrice
        if let newCAP = item.getNewComparePrice(comparedWith: variant){
            addMismatch("Compare at Price mismatch (should be \(newCAP)", item: itemCAP == nil ? "None" : "\(itemCAP!)", shopify: variantCAP ?? "None")
            return false
        }else{
            return true
        }
    }

    mutating func optionsMatch()->Bool{
        let options = item.getOptions()
        if let opt1 = variant.option1{
            guard options.count>0 else{
                addMismatch("No item options", item: "None", shopify: opt1)
                return false
            }
            guard options[0].value == opt1 else{
                addMismatch("Option 1 value", item: options[0].value, shopify: opt1)
                return false
            }
        }
        if let opt2 = variant.option2{
            guard options.count>1 else{
                addMismatch("No second option", item: "None", shopify: opt2)
                return false
            }
            guard options[1].value == opt2 else{
                addMismatch("Option 2 value", item: options[1].value, shopify: opt2)
                return false
            }
        }
        if let opt3 = variant.option3{
            guard options.count>2 else{
                addMismatch("No third option", item: "None", shopify: opt3)
                return false
            }
            guard options[2].value == opt3 else{
                addMismatch("Option 3 value", item: options[2].value, shopify: opt3)
                return false
            }
        }
        return true
    }
    mutating func barcodeMatches()->Bool{
        if let variantBarcode = variant.barcode{
            if item.listItemBarcodes.contains(where: {$0.barcode == variantBarcode}){
                return true
            }else{
                addMismatch("Barcode", item: item.listItemBarcodes.map{$0.barcode}.joined(separator: ", "), shopify: variantBarcode)
                return false
            }
        }else{
            if item.listItemBarcodes.isEmpty{
                return true
            }else{
                addMismatch("Missing Barcode from variant", item: item.listItemBarcodes.map{$0.barcode}.joined(separator: ", "), shopify: "None")
                return false
            }
        }
    }
    mutating func matches()->Bool{
        reset()
        return
            titleMatches()
        && priceMatches()
        && comparePriceMatches()
        && optionsMatch()
        && barcodeMatches()
    }
    mutating func somethingIsWrong() -> [String]? {
        if matches(){
            return nil
        }else{
            return errors
        }
    }
}


