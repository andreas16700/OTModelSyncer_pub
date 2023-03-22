//
//  File.swift
//  
//
//  Created by Andreas Loizides on 06/12/2022.
//
public var versionOfOTModelSyncer = 0.1
import Foundation
import ShopifyKit
import PowersoftKit


var theLog = [String]()
func log(_ message: String){
	theLog.append(message)
}

extension Collection{
	@inlinable
	func toDictionaryArray<K: Hashable>(usingKP kp: KeyPath<Element,K>)-> [K:[Element]]{
		return reduce(into: [K:[Element]](minimumCapacity: count)){
			$0[$1[keyPath: kp], default: .init()].append($1)
		}
	}
	@inlinable
	func toDictionary<K: Hashable>(usingKP kp: KeyPath<Element,K>) -> [K:Element]{
		return reduce(into: [K:Element](minimumCapacity: count)){
			$0[$1[keyPath: kp]]=$1
		}
	}
}
public extension SHProduct{
	static func partiallySynced(with items: [PSItem], stocksByItemCode: inout [String: Int], using: inout RandomNumberGenerator)->Self{
		
		let items = items.shuffled(using: &using)
		let c = items.count
		let u = Int.random(in: 0..<c, using: &using)
		let pf = c - u
		let p = Int.random(in: 0..<pf, using: &using)
		let f = pf-p
		
		let unsynced = items[0..<u]
		var partiallySynced = Array(items[u..<p+u])
		let fullySynced = items[p+u..<f+p+u]
		///
		///items
		///C: count (all items)
		///P: partially synced
		///F: fully synced
		///
		///C = U+P+F
		///0		[]		[]		[]
		///		U	       U+P	     U+P+F
		///
		for i in 0..<partiallySynced.count{
			
			
			partiallySynced[i].listItemBarcodes = partiallySynced[i].listItemBarcodes.map{d in
				var d = d
				d.barcode = String(d.barcode.shuffled(using: &using))
				return d
			}
			partiallySynced[i].priceIncl1 = Double.random(in: 1...9999, using: &using)
			partiallySynced[i].priceIncl3 = Double.random(in: 1...9999, using: &using)
		}
		let syncedAndPartial = partiallySynced + fullySynced
		
		
		//unsynced items shall have no stock
		for item in unsynced{
			stocksByItemCode.removeValue(forKey: item.itemCode365)
		}
		//some of the partially synced items shall have wrong stock
		let itemsWithWrongStock = Int.random(in: 0...p, using: &using)
		var i=0
		for item in syncedAndPartial.shuffled(using: &using){
			let key = item.itemCode365
			if i<itemsWithWrongStock{
				stocksByItemCode[key]=Int.random(in: 0..<999, using: &using)
				i+=1
			}else{
				break
			}
		}
		
		let product = try! syncedAndPartial.getAsNewProduct()
		
		return product
	}
}
extension Collection{
	func mapChangingProperty<T>(kp: WritableKeyPath<Self,T>, to: T)->Self{
		var m = self
		m[keyPath: kp] = to
		return m
	}
}
public struct Xorshift128Plus: RandomNumberGenerator {
	private var xS: UInt64
	private var yS: UInt64
	
	/// Two seeds, `x` and `y`, are required for the random number generator (default values are provided for both).
	public init(xSeed: UInt64 = 0, ySeed:  UInt64 = UInt64.max) {
		xS = xSeed == 0 && ySeed == 0 ? UInt64.max : xSeed // Seed cannot be all zeros.
		yS = ySeed
	}
	
	mutating public func next() -> UInt64 {
		var x = xS
		let y = yS
		xS = y
		x ^= x << 23 // a
		yS = x ^ y ^ (x >> 17) ^ (y >> 26) // b, c
		return yS &+ y
	}
}
