import Foundation

extension NSAppleEventDescriptor {
    /// Converts an NSAppleEventDescriptor to a Swift object
    func toObject() -> Any? {
        switch self.descriptorType {
        case typeAEList:
            // Handle lists
            var array = [Any]()
            for i in 0..<self.numberOfItems {
                if let item = self.atIndex(i+1)?.toObject() {
                    array.append(item)
                }
            }
            return array
            
        case typeAERecord:
            // Handle records (convert to dictionaries)
            var dict = [String: Any]()
            for i in 0..<self.numberOfItems {
                if let key = self.keywordForDescriptor(at: i+1),
                   let keyString = keyToString(key),
                   let value = self.atIndex(i+1)?.toObject() {
                    dict[keyString] = value
                }
            }
            return dict
            
        case typeChar, typeUTF8Text, typeUTF16ExternalRepresentation:
            // Handle strings
            return self.stringValue
            
        case typeTrue:
            // Handle boolean true
            return true
            
        case typeFalse:
            // Handle boolean false
            return false
            
        case typeShortInteger, typeSInt16:
            // Handle 16-bit integers
            return Int(self.int16Value)
            
        case typeSInt32:
            // Handle 32-bit integers
            return Int(self.int32Value)
            
        case typeSInt64:
            // Handle 64-bit integers
            return Int(self.int64Value)
            
        case typeIEEE32BitFloatingPoint:
            // Handle 32-bit floats
            return Float(self.float32Value)
            
        case typeIEEE64BitFloatingPoint:
            // Handle 64-bit floats
            return Double(self.float64Value)
            
        case typeNull:
            // Handle null values
            return nil
            
        default:
            // For other types, try to get the string value
            return self.stringValue
        }
    }
    
    /// Converts an AEKeyword to a string
    private func keyToString(_ key: AEKeyword) -> String? {
        let keyValue = UInt32(key)
        
        // Convert the 4-byte code to a string
        let a = Character(UnicodeScalar((keyValue >> 24) & 0xFF)!)
        let b = Character(UnicodeScalar((keyValue >> 16) & 0xFF)!)
        let c = Character(UnicodeScalar((keyValue >> 8) & 0xFF)!)
        let d = Character(UnicodeScalar(keyValue & 0xFF)!)
        
        return String([a, b, c, d])
    }
} 