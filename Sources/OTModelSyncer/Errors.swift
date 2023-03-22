//
//  Errors.swift
//  
//
//  Created by Andreas Loizides on 05/12/2022.
//

import Foundation
func printDiag(_ message: String){
	print(message)
}
func errorPrint(_ message: String){
	print(message)
}
public struct CouldNotDecode:Error, Codable{
	let response: String
	let decodingError: String
	var isNotFound: Bool {response.contains("Not found")}
}
public struct ErrorSyncing: Error, Codable, Hashable{
	init(name: String, entity: String, description: String, information: [String : String]) {
		self.name = name
		self.entity = entity
		self.description = description
		self.information = information
	}
	
	let name: String
	let entity: String
	let description: String
	let information: [String: String]
	
	init(_ err: Error){
		guard let asCustomErrorType = err as? ErrorSyncing else{
			guard let asDecodingError = err as? CouldNotDecode else{
				self = ErrorSyncing.describing(err: err)
				return
			}
			self = ErrorSyncing(name: "Bad Shopify Response", entity: "Syncer", description: "Unexpected shopify response received,", information: [
				"Response":asDecodingError.response
				,"Decoding Error":asDecodingError.decodingError
			])
			return
		}
		self = asCustomErrorType
	}
	static func describing(err: Error)->ErrorSyncing{
		return ErrorSyncing(name: "Invalid State - Invalid Error Type", entity: "Syncer", description: "Could not downcast error to \(ErrorSyncing.self). Raw error: \(err)", information: [String:String]())
	}
}

struct DecodingErrorWithPayload: Error{
	let originalError: DecodingError
	let payload: Data
	let asString: String?
	init(originalError: DecodingError, payload: Data) {
		self.originalError = originalError
		self.payload = payload
		self.asString = String(data: payload, encoding: .utf8)
	}
}
