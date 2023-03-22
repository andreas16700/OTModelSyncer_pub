//
//  File 2.swift
//  
//
//  Created by Andreas Loizides on 10/10/2022.
//

import Foundation
extension SingleModelSync{
	
	mutating func storeAndThrowError(_ e: ErrorType)throws{
		addError(e)
		throw e
	}
	mutating func storeErrorAndRethrow<T>(_ cl: ()throws->  T?)rethrows->T?{
		do{
			return try cl()
		}catch{
			addError(error)
			throw error
		}
	}
	mutating func storeErrorAndRethrow<T>(_ cl: ()throws->  T)rethrows->T{
		do{
			return try cl()
		}catch{
			addError(error)
			throw error
		}
	}
}
