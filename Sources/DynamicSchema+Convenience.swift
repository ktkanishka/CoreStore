//
//  DynamicSchema+Convenience.swift
//  CoreStore
//
//  Copyright © 2017 John Rommel Estropia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import CoreData
import Foundation


// MARK: - DynamicSchema

public extension DynamicSchema {
    
    /**
     Prints the `DynamicSchema` as their corresponding `CoreStoreObject` Swift declarations. This is useful for converting current `XcodeDataModelSchema`-based models into the new `CoreStoreSchema` framework. Additional adjustments may need to be done to the generated source code; for example: `Transformable` concrete types need to be provided, as well as `default` values.
     
     - Important: After transitioning to the new `CoreStoreSchema` framework, it is recommended to add the new schema as a new version that the existing versions' `XcodeDataModelSchema` can migrate to. It is discouraged to load existing SQLite files created with `XcodeDataModelSchema` directly into a `CoreStoreSchema`.
     - returns: a string that represents the source code for the `DynamicSchema` as their corresponding `CoreStoreObject` Swift declarations.
     */
    public func printCoreStoreSchema() -> String {
        
        let model = self.rawModel()
        let entitiesByName = model.entitiesByName
        
        var output = "/// Generated by CoreStore on \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))\n"
        var addedInverse: Set<String> = []
        for (entityName, entity) in entitiesByName {
            
            let superName: String
            if let superEntity = entity.superentity {
                
                superName = superEntity.name!
            }
            else {
                
                superName = String(describing: CoreStoreObject.self)
            }
            output.append("class \(entityName): \(superName) {\n")
            defer {
                
                output.append("}\n")
            }
            
            let attributesByName = entity.attributesByName
            if !attributesByName.isEmpty {
                
                output.append("    \n")
                for (attributeName, attribute) in attributesByName {
                    
                    let containerType: String
                    if attribute.attributeType == .transformableAttributeType {
                        
                        if attribute.isOptional {
                            
                            containerType = "Transformable.Optional"
                        }
                        else {
                            
                            containerType = "Transformable.Required"
                        }
                    }
                    else {
                        
                        if attribute.isOptional {
                            
                            containerType = "Value.Optional"
                        }
                        else {
                            
                            containerType = "Value.Required"
                        }
                    }
                    let valueType: Any.Type
                    var defaultString = ""
                    switch attribute.attributeType {
                        
                    case .integer16AttributeType:
                        valueType = Int16.self
                        if let defaultValue = (attribute.defaultValue as! Int16.QueryableNativeType?).flatMap(Int16.cs_fromQueryableNativeType) {
                            
                            defaultString = ", initial: \(defaultValue)"
                        }
                    case .integer32AttributeType:
                        valueType = Int32.self
                        if let defaultValue = (attribute.defaultValue as! Int32.QueryableNativeType?).flatMap(Int32.cs_fromQueryableNativeType) {
                            
                            defaultString = ", initial: \(defaultValue)"
                        }
                    case .integer64AttributeType:
                        valueType = Int64.self
                        if let defaultValue = (attribute.defaultValue as! Int64.QueryableNativeType?).flatMap(Int64.cs_fromQueryableNativeType) {
                            
                            defaultString = ", initial: \(defaultValue)"
                        }
                    case .decimalAttributeType:
                        valueType = NSDecimalNumber.self
                        if let defaultValue = (attribute.defaultValue as! NSDecimalNumber?) {
                            
                            defaultString = ", initial: NSDecimalNumber(string: \"\(defaultValue.description(withLocale: nil))\")"
                        }
                    case .doubleAttributeType:
                        valueType = Double.self
                        if let defaultValue = (attribute.defaultValue as! Double.QueryableNativeType?).flatMap(Double.cs_fromQueryableNativeType) {
                            
                            defaultString = ", initial: \(defaultValue)"
                        }
                    case .floatAttributeType:
                        valueType = Float.self
                        if let defaultValue = (attribute.defaultValue as! Float.QueryableNativeType?).flatMap(Float.cs_fromQueryableNativeType) {
                            
                            defaultString = ", initial: \(defaultValue)"
                        }
                    case .stringAttributeType:
                        valueType = String.self
                        if let defaultValue = (attribute.defaultValue as! String.QueryableNativeType?).flatMap(String.cs_fromQueryableNativeType) {
                            
                            // TODO: escape strings
                            defaultString = ", initial: \"\(defaultValue)\""
                        }
                    case .booleanAttributeType:
                        valueType = Bool.self
                        if let defaultValue = (attribute.defaultValue as! Bool.QueryableNativeType?).flatMap(Bool.cs_fromQueryableNativeType) {
                            
                            defaultString = ", initial: \(defaultValue ? "true" : "false")"
                        }
                    case .dateAttributeType:
                        valueType = Date.self
                        if let defaultValue = (attribute.defaultValue as! Date.QueryableNativeType?).flatMap(Date.cs_fromQueryableNativeType) {
                            
                            defaultString = ", initial: Date(timeIntervalSinceReferenceDate: \(defaultValue.timeIntervalSinceReferenceDate))"
                        }
                    case .binaryDataAttributeType:
                        valueType = Data.self
                        if let defaultValue = (attribute.defaultValue as! Data.QueryableNativeType?).flatMap(Data.cs_fromQueryableNativeType) {
                            
                            let count = defaultValue.count
                            let bytes = defaultValue.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
                                
                                return (0 ..< (count / MemoryLayout<UInt8>.size))
                                    .map({ "\("0x\(String(pointer[$0], radix: 16, uppercase: false))")" })
                            }
                            defaultString = ", initial: Data(bytes: [\(bytes.joined(separator: ", "))])"
                        }
                    case .transformableAttributeType:
                        if let attributeValueClassName = attribute.attributeValueClassName {
                            
                            valueType = NSClassFromString(attributeValueClassName)!
                        }
                        else {
                            
                            valueType = (NSCoding & NSCopying).self
                        }
                        if let defaultValue = attribute.defaultValue {
                            
                            defaultString = ", initial: /* \"\(defaultValue)\" */"
                        }
                        else if !attribute.isOptional {
                            
                            defaultString = ", initial: /* required */"
                        }
                    default:
                        fatalError("Unsupported attribute type: \(attribute.attributeType.rawValue)")
                    }
                    let transientString = attribute.isTransient ? ", isTransient: true" : ""
                    // TODO: escape strings
                    let versionHashModifierString = attribute.versionHashModifier
                        .flatMap({ ", versionHashModifier: \"\($0)\"" }) ?? ""
                    // TODO: escape strings
                    let renamingIdentifierString = attribute.renamingIdentifier
                        .flatMap({ ($0 == attributeName ? "" : ", renamingIdentifier: \"\($0)\"") as String }) ?? ""
                    output.append("    let \(attributeName) = \(containerType)<\(String(describing: valueType))>(\"\(attributeName)\"\(defaultString)\(transientString)\(versionHashModifierString)\(renamingIdentifierString))\n")
                }
            }
            
            let relationshipsByName = entity.relationshipsByName
            if !relationshipsByName.isEmpty {
                
                output.append("    \n")
                for (relationshipName, relationship) in relationshipsByName {
                    
                    let containerType: String
                    var minCountString = ""
                    var maxCountString = ""
                    if relationship.isToMany {
                        
                        let minCount = relationship.minCount
                        let maxCount = relationship.maxCount
                        if relationship.isOrdered {
                            
                            containerType = "Relationship.ToManyOrdered"
                        }
                        else {
                            
                            containerType = "Relationship.ToManyUnordered"
                        }
                        if minCount > 0 {
                            
                            minCountString = ", minCount: \(minCount)"
                        }
                        if maxCount > 0 {
                            
                            maxCountString = ", maxCount: \(maxCount)"
                        }
                    }
                    else {
                        
                        containerType = "Relationship.ToOne"
                    }
                    var inverseString = ""
                    let relationshipQualifier = "\(entityName).\(relationshipName)"
                    if !addedInverse.contains(relationshipQualifier),
                        let inverseRelationship = relationship.inverseRelationship {
                        
                        inverseString = ", inverse: { $0.\(inverseRelationship.name) }"
                        addedInverse.insert("\(relationship.destinationEntity!.name!).\(inverseRelationship.name)")
                    }
                    var deleteRuleString = ""
                    if relationship.deleteRule != .nullifyDeleteRule {
                        
                        switch relationship.deleteRule {
                            
                        case .cascadeDeleteRule:
                            deleteRuleString = ", deleteRule: .cascade"
                            
                        case .denyDeleteRule:
                            deleteRuleString = ", deleteRule: .deny"
                            
                        case .nullifyDeleteRule:
                            deleteRuleString = ", deleteRule: .nullify"
                            
                        default:
                            fatalError("Unsupported delete rule \((relationship.deleteRule)) for relationship \"\(relationshipQualifier)\"")
                        }
                    }
                    let versionHashModifierString = relationship.versionHashModifier
                        .flatMap({ ", versionHashModifier: \"\($0)\"" }) ?? ""
                    let renamingIdentifierString = relationship.renamingIdentifier
                        .flatMap({ ($0 == relationshipName ? "" : ", renamingIdentifier: \"\($0)\"") as String }) ?? ""
                    output.append("    let \(relationshipName) = \(containerType)<\(relationship.destinationEntity!.name!)>(\"\(relationshipName)\"\(inverseString)\(deleteRuleString)\(minCountString)\(maxCountString)\(versionHashModifierString)\(renamingIdentifierString))\n")
                }
            }
        }
        output.append("\n\n\n")
        output.append("CoreStoreSchema(\n")
        output.append("    modelVersion: \"\(self.modelVersion)\",\n")
        output.append("    entities: [\n")
        for (entityName, entity) in entitiesByName {
            
            var abstractString = ""
            if entity.isAbstract {
                
                abstractString = ", isAbstract: true"
            }
            var versionHashModifierString = ""
            if let versionHashModifier = entity.versionHashModifier {
                
                versionHashModifierString = ", versionHashModifier: \"\(versionHashModifier)\""
            }
            output.append("        Entity<\(entityName)>(\"\(entityName)\"\(abstractString)\(versionHashModifierString)),\n")
        }
        output.append("    ],\n")
        output.append("    versionLock: \(VersionLock(entityVersionHashesByName: model.entityVersionHashesByName).description.components(separatedBy: "\n").joined(separator: "\n    "))\n")
        output.append(")\n\n")
        return output
    }
}
