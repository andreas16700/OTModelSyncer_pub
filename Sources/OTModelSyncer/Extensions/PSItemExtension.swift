//
//  File.swift
//  
//
//  Created by Andreas Loizides on 27/04/2020.
//

import Foundation
import PowersoftKit
import ShopifyKit
public struct PSOption{
	public let name: String
	public let value: String
}

extension Dictionary where Value: Identifiable, Key == Value.ID{
	init(fromArray array: [Value]){
		self = array.reduce(into: Dictionary<Value.ID, Value>()){
			$0[$1.id]=$1
		}
	}
}



extension Collection where Element == PSItem{
    func getSHOptions()throws->[SHOption]{
        let dict = try self.reduce(into: [Int: SHOption]()){options, item in
            for index in 1...3{
                if let itemOption = item.getOption(index: index){
                    if options[index] == nil{
                        options[index] = SHOption(id: nil, productID: nil, name: itemOption.name, position: index, values: [itemOption.value])
                    }else{
                        if !options[index]!.values.contains(itemOption.value){
                            options[index]!.values.append(itemOption.value)
                        }
                        if itemOption.name != options[index]!.name{
                            let itemsWithPreviousOpiton = self.filter{$0.getOption(index: index)?.name == options[index]!.name}
                            let itemsWithThisOption = self.filter{$0.getOption(index: index)?.name == itemOption.name}
                            let eitherOption = itemsWithThisOption + itemsWithPreviousOpiton
                            var dict = eitherOption.reduce(into: [String: String]()){dict, item in
                                dict["\(item.itemCode365) computed options"]=item.getOptions().map{$0.asString()}.joined(separator: ",")
                                dict["\(item.itemCode365) colorName"]=item.colorName
                                dict["\(item.itemCode365) sizeName"]=item.sizeName
                            }
                            dict["Items with option \(index) as \(options[index]!.name)"]=itemsWithPreviousOpiton.map{$0.itemCode365}.joined(separator: ",")
                            dict["Items with option \(index) as \(itemOption.name)"]=itemsWithThisOption.map{$0.itemCode365}.joined(separator: ",")
                            throw ErrorSyncing(name: "PSItems option mismatch", entity: "Syncer"
                                               ,description: "item \(item.itemCode365) has option \(index) name \(itemOption.name) but another item has \(options[index]!.name)!"
                                               ,information: dict)
                        }
                    }
                }
            }
        }
		let f = dict.sorted(by: {$0.key < $1.key})
		return f.map(\.value)
    }
    func getNewOptions(comparedWith existing: SHProduct)throws->[SHOption]?{
		let optionsUnmodified = try getSHOptions()
        guard let existingOptions = existing.options else{
			return optionsUnmodified.isEmpty ? nil : optionsUnmodified
        }
		let options = optionsUnmodified.matchedIDsOf(other: existingOptions)
        guard options.count == existingOptions.count else{
            return options
        }
        guard existingOptions.allSatisfy({$0.position != nil}) else{
            return options
        }
        let sortedExisting = existingOptions.sorted(by: {$0.position!<$1.position!})
        let sortedNew = options.sorted(by: {$0.position!<$1.position!})
        for i in 0..<sortedExisting.count{
            let existingOption = sortedExisting[i]
            let newOption = sortedNew[i]
            guard existingOption.name == newOption.name && Set(existingOption.values) == Set(newOption.values) else{
                return options
            }
        }
        return nil
    }
    func checkIntegrityAsModelItems()throws{
        guard let first=first else{return}
        let _ = try getSHOptions()
        let model = first.modelCode365
        func propertyMismatchError(propertyName: String, oneValue: String, other: String)->Error{
            return ErrorSyncing(name: "Model PSItems property mismatch", entity: "Syncer", description: "Items belonging to the same model (\(model)) have conflicting properties that should be common", information: [
                "items contained in this model":self.map{$0.itemCode365}.joined(separator: ",")
                ,"\(propertyName)":"found \(oneValue) and \(other)"
            ])
        }
        let title = first.computeModelTitle()
        var other: String?
        guard allSatisfy({
            other = $0.computeModelTitle()
            return other!==title
        })else{
            throw propertyMismatchError(propertyName: "title", oneValue: title, other: other!)
        }
        
        let vendor = first.getVendor()
        guard allSatisfy({
            other = $0.getVendor()
            return vendor == other!
        })else{
            throw propertyMismatchError(propertyName: "vendor", oneValue: vendor, other: other!)
        }
        let tags = first.computeSHTag()
        guard allSatisfy({
            other = $0.computeSHTag()
            return tags == other!
        })else{
            throw propertyMismatchError(propertyName: "tags", oneValue: tags, other: other!)
        }
        let body = first.computeSHDescription()
        guard allSatisfy({
            other = $0.computeSHDescription()
            return body == other
        })else{
            throw propertyMismatchError(propertyName: "body html", oneValue: body, other: other!)
        }
        let optionNames = first.getOptionNames()
        var otherOptionNames = [String]()
        guard allSatisfy({
            otherOptionNames = $0.getOptionNames()
            return optionNames == otherOptionNames
        })else{
            throw propertyMismatchError(propertyName: "option names", oneValue: optionNames.joined(separator: ","), other: otherOptionNames.joined(separator: ","))
        }
                
    }
    func hasProductUpdate(current shProd: SHProduct, ingoreExistingProductDescr: Bool = true)throws->SHProductUpdate?{
        guard let validID = shProd.id else{
            throw ErrorSyncing(name: "Missing Product ID", entity: "Syncer", description: "Called to update product \(shProd.handle) but it has no ID!", information: [
                "Last updated":"\(shProd.updatedAt ?? "no value!")"
            ])
        }
        try checkIntegrityAsModelItems()
        guard let item = first else{return nil}
        var newBody: String?
        if !ingoreExistingProductDescr{
            newBody = item.getNewBodyHTML(comparedWith: shProd)
        }
        let newTag = item.getNewTag(comparedWith: shProd)
        let newTitle = item.getNewTitlecomparedWith(product: shProd)
        let newVendor = item.getNewVendor(comparedWith: shProd)
        let newType = item.getNewProductType(comparedWith: shProd)
        let newOptions = try getNewOptions(comparedWith: shProd)
        var atLeastOneVariantUpdate=false
        let variantUpdates:[SHVariantUpdate] = try self.map{itm in
            if let existingVariant = shProd.variants.first(where: {$0.sku==itm.itemCode365}){
                if let update = try itm.hasVariantUpdate(currentVariant: existingVariant, updateOptions: true){
                    atLeastOneVariantUpdate=true
                    return update
                }else{
                    return SHVariantUpdate(id: existingVariant.id!)
                }
            }else{
                atLeastOneVariantUpdate=true
                return itm.asNewVariant()
            }
        }
        if newBody != nil || newTag != nil || newTitle != nil || newVendor != nil || newType != nil || newOptions != nil{
            let update = SHProductUpdate(id: validID, title: newTitle, published: nil, body_html: newBody, tags: newTag, vendor: newVendor, variants: atLeastOneVariantUpdate ? variantUpdates : nil, options: newOptions, product_type: newType, image: nil, images: nil)
            return update
        }
        return nil
    }
    
    public func getAsNewProduct()throws->SHProduct{
        try checkIntegrityAsModelItems()
        guard let first = first else{
            throw ErrorSyncing(name: "Invalid state - Empty model", entity: "Syncer", description: "Called to conpublic struct product for model that is empty", information: ["date called":"\(Date())"])
        }
        let variants = map{SHVariant(from: $0)}
        let body = first.computeSHDescription()
        let options = try getSHOptions()
        let title = first.computeModelTitle()
        let tags = first.computeSHTag()
        let vendor = first.getVendor()
        let handle = first.getShHandle()
        return SHProduct(id: nil, title: title, bodyHTML: body, vendor: vendor, productType: first.getProductType(), createdAt: nil, handle: handle, updatedAt: nil, publishedAt: nil, templateSuffix: nil, publishedScope: "web", tags: tags, adminGraphqlAPIID: nil, variants: variants, options: options, images: nil, image: nil)
    }
}
extension Optional where Wrapped == Double{
    func asStringIfExists()->String?{
		if let value = self{
            return "\(value)"
        }else{
            return nil
        }
    }
}
extension PSItem{
    func asNewVariant()->SHVariantUpdate{
		return SHVariantUpdate(id: nil, option1: getOption1(name: false), option2: getOption2(name: false), option3: getOption3(name: false), price: "\(computeSHPrice())", compare_at_price: computeSHComparePrice().asStringIfExists(), sku: itemCode365, title: computeSHVariantTitle(), barcode: getBarcode())
    }
	func hasProductSpecificOnlyUpdate(existing shProd: SHProduct, ingoreExistingProductDescr: Bool = true, ignoringOptions: Bool = true)throws->SHProductUpdate?{
		if !ignoringOptions{fatalError("No support for options update in item-only context")}
		guard let validID = shProd.id else{
			throw ErrorSyncing(name: "Missing Product ID", entity: "Syncer", description: "Called to update product \(shProd.handle) but it has no ID!", information: [
				"Last updated":"\(shProd.updatedAt ?? "no value!")"
			])
		}
		let item = self
		var newBody: String?
		if !ingoreExistingProductDescr{
			newBody = item.getNewBodyHTML(comparedWith: shProd)
		}
		let newTag = item.getNewTag(comparedWith: shProd)
		let newTitle = item.getNewTitlecomparedWith(product: shProd)
		let newVendor = item.getNewVendor(comparedWith: shProd)
		let newType = item.getNewProductType(comparedWith: shProd)
		if newBody != nil || newTag != nil || newTitle != nil || newVendor != nil || newType != nil{
			let update = SHProductUpdate(id: validID, title: newTitle, published: nil, body_html: newBody, tags: newTag, vendor: newVendor, variants: nil, options: nil, product_type: newType, image: nil, images: nil)
			return update
		}
		return nil
	}
    func hasVariantUpdate(currentVariant shVar: SHVariant, updateOptions: Bool)throws->SHVariantUpdate?{
        guard let validID = shVar.id else{
            throw ErrorSyncing(name: "Missing Variant ID", entity: "Syncer", description: "Called to update variant \(shVar.sku) for item \(itemCode365) but the variant has no ID!", information: [
                "Last updated":"\(shVar.updatedAt ?? "no value!")"
            ])
        }
        let newTitle = getNewTitle(comparedWith: shVar)
        var newPrice = getNewPrice(comparedWith: shVar)
        var newCompare = getNewComparePrice(comparedWith: shVar)
        let newBarcode = getNewBarcode(comparedWith: shVar)
        
        let newOption1 = updateOptions ? getNewOption1(comparedWith: shVar) : nil
        let newOption2 = updateOptions ? getNewOption2(comparedWith: shVar) : nil
        let newOption3 = updateOptions ? getNewOption3(comparedWith: shVar) : nil
        if newTitle != nil || newPrice != nil || newCompare != nil || newOption1 != nil || newOption2 != nil || newOption3 != nil || newBarcode != nil{
            
            if let newComp = newCompare{
                if newComp=="0"{
                    newCompare=""
                    newPrice = "\(computeSHPrice())"
                }
            }
            
            let update = SHVariantUpdate(id: validID, option1: newOption1, option2: newOption2, option3: newOption3, price: newPrice, compare_at_price: newCompare, title: newTitle, barcode: newBarcode)
            
            return update
        }
        return nil
    }
    
    
    func optionsContained(currentOptions: [SHOption])->Bool{
        if let _ = getNewOptionsNames(currentOptions: currentOptions){
            return false
        }
        return true
    }
    
    func getNewOptionsNames(currentOptions: [SHOption])->[String]?{
        let psOpts = getOptionNames()
        var newOpts = [String]()
        for opt in psOpts{
            if !currentOptions.contains(where: {$0.name == opt}){
                newOpts.append(opt)
            }
        }
        if newOpts.isEmpty{
            return nil
        }
        return newOpts
        
    }
    public func getOptionNames()->[String]{
        var opts = [String]()
        //option 1
        let opt1Name = getOption1(name: true)
        opts.append(opt1Name)
        if let opt2Name = getOption2(name: true){
            opts.append(opt2Name)
        }
        if let opt3Name = getOption3(name: true){
            opts.append(opt3Name)
        }
        return opts
    }
	public func getOptions()->[PSOption]{
		var options = [PSOption]()
		for i in 1...3{
			if let option = getOption(index: i){
				options.append(option)
            }else{
                break
            }
		}
		return options
	}
	public func getOption(index: Int)->PSOption?{
		let name: String?
		let value: String?
		switch index{
		case 1:
			name=getOption1(name: true)
			value=getOption1(name: false)
		case 2:
			name=getOption2(name: true)
			value=getOption2(name: false)
		case 3:
			name=getOption3(name: true)
			value=getOption3(name: false)
		default:
			return nil
		}
		guard name != nil, value != nil else{return nil}
		return PSOption(name: name!, value: value!)
	}
	public func getCleanColorValue()->String{
		let keywordsToIgnoreAndRemoveForFirstOption = [
			"Right","R",
			"Left","L",
			"Women","Woman","W","F",
			"Men","Man","M",
		]
		let separators = ["-","/"," ","_"]
		func getOnlyColorValue()->String{
			let keywordsWithSeparators = keywordsToIgnoreAndRemoveForFirstOption.reduce(into: [String]()) {arr, keyword in
				let withSeparatorFromLeft = separators.map{$0+keyword}
				arr.append(contentsOf: withSeparatorFromLeft)
			}
			var c = colorName
			keywordsWithSeparators.forEach{keyword in
				if c.lowercased().hasSuffix(keyword.lowercased()){
					c = String(c.dropLast(keyword.count))
				}
			}
			return c
		}
		return getOnlyColorValue()
	}
	public func getOption1(name: Bool)->String{
        if getOption3(name: false) != nil{
            let arr = Array(colorCode365)
            guard arr.count>1 else{errorPrint("color code \(colorCode365) is not more than 1 char long!!");return colorName}
            let color = arr.dropLast()
            let s = String(color)
            switch s {
                //Check for user defined exceptions
            case "BLU":
                return name ? "Color" : "BLUE"
            case "BL":
                return name ? "Color" : "BLACK"
            default:
				return name ? "Color" : getCleanColorValue()
            }
            
        }
        if getOption2(name: false) != nil{
            return name ? "Size" : sizeName
        }
        return name ? "Title" : "Default Title"
    }
    func getNewOption1(comparedWith variant:SHVariant)->String?{
        let psOpt = getOption1(name: false)
        guard let shOp1 = variant.option1 else {return psOpt}
        if psOpt != shOp1{
            return psOpt
        }
        return nil
    }
    public func getOption2(name: Bool)->String?{
        if getOption3(name: false) != nil{
            //if there is opt3 then opt2 is size
            
            return name ? "Size" : sizeName
        }
        //no opt2 -> no opt2 lol
        guard colorName != "" else {return nil}
        //no option3  and option2 exists -> opt2 is color
        return name ? "Color" : colorName
    }
    func getNewOption2(comparedWith variant:SHVariant)->String?{
        guard let psOpt = getOption2(name: false) else{return nil}
        guard let shOpt = variant.option2 else{return psOpt}
        if psOpt != shOpt {
            return psOpt
        }
        return nil
    }
    public func getOption3(name: Bool)->String?{
        guard colorName != "" else{return nil}
        func existsAsSeparated(word: String, thing: String)->Bool{
            let separators = ["-","/"," ","_"]
            let cs = CharacterSet(charactersIn: separators.joined())
            let components = word.components(separatedBy: cs)
            return components.contains(thing)
        }
        if existsAsSeparated(word: colorName, thing: "RIGHT"){
            return name ? "Orientation" : "Right"
        }
        if existsAsSeparated(word: colorName, thing: "LEFT"){
            return name ? "Orientation" : "Left"
        }
        if existsAsSeparated(word: colorName, thing: "W"){
            return name ? "Gender" : "Women"
        }
        if existsAsSeparated(word: colorName, thing: "M"){
            return name ? "Gender" : "Men"
        }
        if existsAsSeparated(word: colorName, thing: "R"){
            return name ? "Orientation" : "Right"
        }
        if existsAsSeparated(word: colorName, thing: "L"){
            return name ? "Orientation" : "Left"
        }
        return nil
    }
    func getNewOption3(comparedWith variant:SHVariant)->String?{
        guard let psOpt = getOption3(name: false) else{return nil}
        guard let shOpt = variant.option3 else{return psOpt}
        if psOpt != shOpt {
            return psOpt
        }
        return nil
    }
    public func computeSHVariantTitle()->String{
        let opt1 = getOption1(name: false)
        if let opt3 = getOption3(name: false){
            guard let opt2 = getOption2(name: false) else{
                return "\(opt1) /  / \(opt3)"
            }
            return "\(opt1) / \(opt2) / \(opt3)"
        }
        if let opt2 = getOption2(name: false){
            return "\(opt1) / \(opt2)"
        }
        return opt1
    }
    func getNewTitle(comparedWith variant:SHVariant)->String?{
        let psT = computeSHVariantTitle()
        if variant.title != psT{
            let setA = Set(variant.title)
            let setB = Set(psT)
            let diff = setA.union(setB).subtracting(setA.intersection(setB))
            if (diff.isEmpty){return nil}
            return psT
        }
        return nil
    }
    public func isDiscounted()->Bool{
        if (priceIncl1 != priceIncl3) && (priceIncl1 + 0.01 != priceIncl3) && (priceIncl1 != priceIncl3 + 0.01) && (priceIncl3<priceIncl1) && (priceIncl3 != 0){
            return true
        }
        return false
    }
    public func computeSHPrice()->Double{
        if isDiscounted(){
            return priceIncl3
        }
        return priceIncl1
    }
    func getNewPrice(comparedWith variant:SHVariant)->String?{
        let currentPS = computeSHPrice()
        guard let shDouble = Double(variant.price) else{
            errorPrint("FAILED TO CONVERT SH PRICE TO DOUBLE!!")
            return "\(currentPS)"
        }
        if shDouble != currentPS && shDouble != currentPS+0.01 && shDouble+0.01 != currentPS{
            let diff = currentPS-shDouble
            print("price difference: \(diff)")
            return "\(computeSHPrice())"
        }
        return nil
    }
    public func computeSHComparePrice()->Double?{
        if isDiscounted(){
        return priceIncl1
        }
        return nil
    }
    public func getNewComparePrice(comparedWith variant:SHVariant)->String?{
        if let currentCompare = variant.compareAtPrice{
            //there's already a price
            if let compareDouble = Double(currentCompare){
                //it's a valid number, compare it
                if let newCompare = computeSHComparePrice(){
                    if newCompare != compareDouble{
                        //if the new compare exists, return that
                        return "\(newCompare)"
                    }else{
                        //no change
                        return nil
                    }
                }else{
                    //new compare does not exist
                    guard let priceD = Double(variant.price) else{ return nil }
                    if compareDouble == priceD || compareDouble+0.01 == priceD || compareDouble == priceD+0.01{
                        //if it was not previously on sale, and it's not now then do nothing
                        return nil
                    }
                    //if the new does not exist then return nil (item is not on sale anymore) note that the price should be sent to shopify
                    return "0"
                }
            }else{
                //sh price is not a number
                if let newCompare = computeSHComparePrice(){
                    //if  there should be a compare price then return that
                    return "\(newCompare)"
                }else{
                    //no change
                    return nil
                }
            }
        }else{
            //there's no compare price
            if let newCompare = computeSHComparePrice(){
                //product is now on sale
                return "\(newCompare)"
            }else{
                //no change
                return nil
            }
        }
    }
    public func getBarcode()->String{
        guard let first = listItemBarcodes.first else{return ""}
        if let firstPreferred = listItemBarcodes.first(where: {$0.isLabelBarcode==false}){
            return firstPreferred.barcode
        }else{
            return first.barcode
        }
    }
    func getNewBarcode(comparedWith variant:SHVariant)->String?{
        guard let existing = variant.barcode else{
            return getBarcode()
        }
        
        let newBarcode = getBarcode()
        if newBarcode != existing{
            return newBarcode
        }else{
            return nil
        }
    }
    //-------PRODUCT SPECIFIC---------
    
    public func computeModelTitle()->String{
        if itemName == ""{
            return modelName
        }
        return itemName
    }
    func getNewTitlecomparedWith(product: SHProduct)->String?{
        if computeModelTitle() != product.title{
            let setA = Set(computeModelTitle())
            let setB = Set(product.title)
            let diff = setA.union(setB).subtracting(setA.intersection(setB))
            if (diff.isEmpty){return nil}
            printDiag("Diff: \(diff)")
            return computeModelTitle()
        }
        return nil
    }
    public func computeSHDescription()->String{
        return specifications + "\n\n" + notes
    }
    public func computeSHTag()->String{
        let psItem = self
        if (psItem.attribute1_Name != "" || psItem.attribute2_Name != "" || psItem.attribute3_Name != ""){
            return "Dept:\(psItem.deptName), Gender:\(psItem.attribute1_Name), \(psItem.getShHandle(lowercased: false)), Rebound:\(psItem.attribute3_Name), Season:\(psItem.seasonName), Style:\(psItem.attribute2_Name)"
        }else{
            return "\(psItem.getShHandle(lowercased: false)), Dept:\(psItem.deptName), Season:\(psItem.seasonName)"
        }
    }
    public func computeAltSHTag()->String{
        return "Dept:\(deptName), \(getShHandle(lowercased: false)), Season:\(seasonName)"
    }
    public func computeOtherAltTag()->String{
        return "Dept:\(deptName), Season:\(seasonName), \(getShHandle(lowercased: false))"
    }
	public func computeOtherOtherAltTag()->String{
		return "\(getShHandle(lowercased: true)), Dept:\(deptName), Season:\(seasonName)"
	}
    public func getShHandle(lowercased: Bool = true)->String{
        let handle: String
        if modelCode365 == ""{
            handle = itemCode365.replacingOccurrences(of: "/", with: "-")
        }else{
            handle = modelCode365.replacingOccurrences(of: "/", with: "-")
        }
        return lowercased ? handle.lowercased() : handle
    }
    func getNewBodyHTML(comparedWith product: SHProduct)->String?{
        func compareDescriptions(originalHTML: String, newString: String)->String?{
            let c1 = originalHTML.replacingOccurrences(of: "<br>", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let c2 = newString.trimmingCharacters(in: .whitespacesAndNewlines)
            if c1==c2{
                return nil
            }
            let setA = Set(c1)
            let setB = Set(c2)
            let diff = setA.union(setB).subtracting(setA.intersection(setB))
            if (diff.isEmpty){return nil}
            printDiag("Diff: \(diff)")
            return newString
        }
        return compareDescriptions(originalHTML: product.bodyHTML ?? "\n\n", newString: computeSHDescription())
    }
    func getNewTag(comparedWith product: SHProduct)->String?{
        if product.tags != computeSHTag() && product.tags != computeAltSHTag() && product.tags != computeOtherAltTag()
			&& product.tags != computeOtherOtherAltTag(){
            let setA = Set(computeSHTag())
            let setB = Set(product.tags)
            let diff = setA.union(setB).subtracting(setA.intersection(setB))
            if (diff.isEmpty){return nil}
            printDiag("Diff: \(diff)")
                return computeSHTag()
            }
            return nil
    }
    public func getVendor()->String{
        if brandName == ""{
            return "Orthohouse"
        }
        return brandName
    }
    func getNewVendor(comparedWith product: SHProduct)->String?{
        if product.vendor != getVendor() && !(getVendor() == " " && (product.vendor == "Orthohouse" || product.vendor == "Orthohousecy")){
            let setA = Set(getVendor())
            let setB = Set(product.vendor)
            let diff = setA.union(setB).subtracting(setA.intersection(setB))
            if (diff.isEmpty){return nil}
            printDiag("Diff: \(diff)")
                return getVendor()
            }
            return nil
    }
    public func getProductType()->String{
        return categoryName
    }
    func getNewProductType(comparedWith product: SHProduct)->String?{
            if product.productType != getProductType(){
                let setA = Set(product.productType)
                let setB = Set(getProductType())
                let diff = setA.union(setB).subtracting(setA.intersection(setB))
                if (diff.isEmpty){return nil}
                printDiag("Diff: \(diff)")
                return getProductType()
            }
            return nil
    }
}
