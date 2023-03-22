//
//  File.swift
//  
//
//  Created by Andreas Loizides on 10/12/2022.
//

import Foundation
import PowersoftKit
import ShopifyKit

public struct ModelsSync: Codable{
	public init(id: String = UUID().uuidString, metadata: ModelsSync.Metadata = Metadata(lastUpdated: .now, state: .created), syncIDByModelCode: [String : String] = [String:String](), inQueueSyncs: [String : String] = [String:String](), interestingDoneSyncs: [String : String] = [String:String](), uninterestingDoneSyncs: [String : String] = [String:String](), failedSyncs: [String : String] = [String:String]()) {
		self.id = id
		self.metadata = metadata
		self.syncIDByModelCode = syncIDByModelCode
		self.inQueueSyncs = inQueueSyncs
		self.interestingDoneSyncs = interestingDoneSyncs
		self.uninterestingDoneSyncs = uninterestingDoneSyncs
		self.failedSyncs = failedSyncs
	}
	
	public var id: String = UUID().uuidString
	
	public private(set) var metadata = Metadata(lastUpdated: .now, state: .created)
	
	public internal(set) var syncIDByModelCode:[String:String]? = [String:String](){
		didSet{
			metadata.lastUpdated = .now
		   }
	   }
	public private(set) var inQueueSyncs:[String:String]? = [String:String](){
		didSet{
			metadata.lastUpdated = .now
		   }
	   }
	public private(set) var interestingDoneSyncs:[String:String]? = [String:String](){
		didSet{
			metadata.lastUpdated = .now
		   }
	   }
	public private(set) var uninterestingDoneSyncs:[String:String]? = [String:String](){
		didSet{
			metadata.lastUpdated = .now
		   }
	   }
	public private(set) var failedSyncs:[String:String]? = [String:String](){
		didSet{
			metadata.lastUpdated = .now
		   }
	   }
	public struct Metadata: Codable{
		public init(lastUpdated: Date, state: SingleModelSync.EndState, failReason: String? = nil) {
			self.lastUpdated = lastUpdated
			self.state = state
			self.failReason = failReason
		}
		
		public var lastUpdated: Date
		public var state: SingleModelSync.EndState{
			didSet{
				lastUpdated = .now
			}
		}
		public var failReason: String?{
			didSet{
				lastUpdated = .now
			}
		}
	}
	public var isInProgress: Bool{
		switch metadata.state{
		case .created:
			return false
		case .waiting:
			return true
		case .done:
			return false
		case .failed:
			return false
		case .incomplete:
			return false
		}
	}
	mutating func syncInitiated(){
		metadata.state = .waiting
	}
	mutating func done(isIncomplete: Bool = false){
		metadata.state = isIncomplete ? .incomplete : .done
	}
	mutating func failed(reason: String){
		metadata.state = .failed
		metadata.failReason = reason
	}
	mutating func addToQueue(modelCode: String, syncID: String){
		if self.inQueueSyncs == nil {self.inQueueSyncs = .init()}
		if self.syncIDByModelCode == nil {self.syncIDByModelCode = .init()}
		self.inQueueSyncs![modelCode]=syncID
		self.syncIDByModelCode![modelCode]=syncID
	}
	mutating func failedSync(modelCode: String, syncID: String){
		self.inQueueSyncs!.removeValue(forKey: modelCode)
		if self.failedSyncs == nil {self.failedSyncs = .init()}
		self.failedSyncs![modelCode]=syncID
	}
	mutating func doneSync(modelCode: String, sync: SingleModelSync){
		self.inQueueSyncs!.removeValue(forKey: modelCode)
		let syncID = sync.id
		if sync.isInteresting(){
			if self.interestingDoneSyncs == nil {self.interestingDoneSyncs = .init()}
			self.interestingDoneSyncs![modelCode] = syncID
		}else{
			if self.uninterestingDoneSyncs == nil {self.uninterestingDoneSyncs = .init()}
			self.uninterestingDoneSyncs![modelCode] = syncID
		}
	}
	public var percentDone: Double{
		guard let allSyncs = syncIDByModelCode, let failedSyncs, let uninterestingDoneSyncs, let interestingDoneSyncs else {return 100}
		let total = Double(allSyncs.count)
		let done = Double(failedSyncs.count + uninterestingDoneSyncs.count + interestingDoneSyncs.count)
		return (done*100)/total
	}
}

extension SingleModelSync{
	func hasNoErrors()->Bool{
		self.metadata.errors == nil
		&&
		self.metadata.syncErrors == nil
		&&
		self.metadata.unknownErrors == nil
		&&
		self.metadata.states.allSatisfy{$0.value != .failed}
	}
	func hasEnded()->Bool{
		self.metadata.ended != nil
	}
	func isInteresting()->Bool{
		guard self.hasEnded()
				&&
				self.hasNoErrors()
		else {return false}
		return self.updates != nil
	}
}
