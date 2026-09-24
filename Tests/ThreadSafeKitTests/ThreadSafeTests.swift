import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

@Test(arguments: mechanisms) func threadSafeArrayShapeAppendPushPop(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    array.append(2)
    array.append(3)
    array.push(1)
    #expect(array.elements == [1, 2, 3])
    #expect(array.pop() == 3)
    #expect(array.count == 2)
    #expect(array.first == 1)
    #expect(array.last == 2)
    #expect(array[safe: 5] == nil)
}

@Test func threadSafeArrayShapeSequenceInit() throws {
    let array = ThreadSafe<[Int]>(0..<5)
    #expect(array.elements == [0, 1, 2, 3, 4])
}

@Test(arguments: mechanisms) func threadSafeDictionaryShapeGetSetRemove(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    dictionary.setValue(1, forKey: "a")
    dictionary["b"] = 2
    #expect(dictionary.getValue(forKey: "a") == 1)
    #expect(dictionary["b"] == 2)
    #expect(dictionary.count == 2)
    #expect(dictionary.removeValue(forKey: "a") == 1)
    dictionary.removeAll()
    #expect(dictionary.isEmpty)
}

@Test(arguments: mechanisms) func threadSafeAtomicShapeMutate(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafe(mechanism: mechanism) var counter = 0
    _counter.mutate { $0 += 1 }
    #expect(counter == 1)
}

@Test func threadSafeShapePropertyWrapperMechanismInit() throws {
    @ThreadSafe var items: [Int] = []
    $items.append(1)
    #expect(items == [1])

    @ThreadSafe var cache: [String: Int] = [:]
    $cache.setValue(1, forKey: "a")
    #expect(cache == ["a": 1])
}
