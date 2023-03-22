//
//  PSItemExtensions.swift
//  
//
//  Created by Andreas Loizides on 05/12/2022.
//

import Foundation
import ShopifyKit
import PowersoftKit
extension Array where Element==SHOption{
	func matchedIDsOf(other: Self)->Self{
		var m = self
		var IDs = other.compactMap(\.id)
		for i in 0..<m.count {
			if m[i].id != nil {continue}
			if let id = IDs.popLast(){
				m[i].id = id
			}
		}
		return m
	}
}
extension SHOption{
	static func makeOptions(fromItems ps: [PSItem])->[SHOption]{
		let options = ps.map{$0.getOptions()}
		
		//										name: values
		let shOptionsDict = options.reduce(into: [String: [String]]()){allShDictionary, psOptions in
			for option in psOptions{
				if allShDictionary[option.name] != nil{
					if !allShDictionary[option.name]!.contains(option.value){
						allShDictionary[option.name]!.append(option.value)
					}
				}else{
					allShDictionary[option.name]=[option.value]
				}
			}
		}
		let shOptions = shOptionsDict.reduce(into: [SHOption]()){allOptions, optionTuple in
			allOptions.append(SHOption(id: nil, productID: nil, name: optionTuple.key, position: nil, values: optionTuple.value))
		}
		return shOptions
	}
}
