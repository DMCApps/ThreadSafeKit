import Foundation
import Testing
@testable import ThreadSafeKit

// Coverage for optional wrapped values and optional elements across every mechanism.

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

// MARK: - Plain optional value shape: ThreadSafe<Int?>

@Test(arguments: mechanisms)
func optionalValueStartsAndReadsNilWithoutCrashing(mechanism: ThreadSafeMechanism) {
    let box = ThreadSafe<Int?>(wrappedValue: nil, mechanism: mechanism)
    #expect(box.wrappedValue == nil)
}

@Test(arguments: mechanisms)
func optionalValueMutateToNilAndBackDoesNotCrash(mechanism: ThreadSafeMechanism) {
    let box = ThreadSafe<Int?>(wrappedValue: 1, mechanism: mechanism)
    box.mutate { $0 = nil }
    #expect(box.wrappedValue == nil)
    box.mutate { $0 = 42 }
    #expect(box.wrappedValue == 42)
    box.mutate { $0 = nil }
    #expect(box.wrappedValue == nil)
}

@Test(arguments: mechanisms)
func optionalValueConcurrentNilTogglingNeverCrashesOrTraps(mechanism: ThreadSafeMechanism) {
    // Flipping nil/non-nil under concurrent reads must not crash.
    let box = ThreadSafe<Int?>(wrappedValue: nil, mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 16) { i in
        if i % 2 == 0 {
            for j in 0..<1_000 {
                box.mutate { $0 = j.isMultiple(of: 2) ? nil : j }
            }
        } else {
            for _ in 0..<1_000 {
                _ = box.wrappedValue
            }
        }
    }
}

// MARK: - Optional array shape: ThreadSafe<[Int]?>
// `Optional<[Int]>` isn't a Collection, so only base members apply.

@Test(arguments: mechanisms)
func optionalArrayStartsNilAndCanBeInitializedViaMutate(mechanism: ThreadSafeMechanism) {
    let box = ThreadSafe<[Int]?>(wrappedValue: nil, mechanism: mechanism)
    #expect(box.wrappedValue == nil)

    box.mutate { array in
        if array == nil { array = [] }
        array?.append(1)
    }
    #expect(box.wrappedValue == [1])

    box.mutate { $0 = nil }
    #expect(box.wrappedValue == nil)
}

@Test(arguments: mechanisms)
func optionalArrayConcurrentNilTogglingNeverCrashes(mechanism: ThreadSafeMechanism) {
    let box = ThreadSafe<[Int]?>(wrappedValue: nil, mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 16) { i in
        if i % 2 == 0 {
            for j in 0..<500 {
                box.mutate { $0 = j.isMultiple(of: 2) ? nil : [j] }
            }
        } else {
            for _ in 0..<500 {
                _ = box.wrappedValue
            }
        }
    }
}

// MARK: - Optional dictionary shape: ThreadSafe<[String: Int]?>
// `Optional<[Key: Value]>` isn't keyed storage, so only base members apply.

@Test(arguments: mechanisms)
func optionalDictionaryStartsNilAndCanBeInitializedViaMutate(mechanism: ThreadSafeMechanism) {
    let box = ThreadSafe<[String: Int]?>(wrappedValue: nil, mechanism: mechanism)
    #expect(box.wrappedValue == nil)

    box.mutate { dictionary in
        if dictionary == nil { dictionary = [:] }
        dictionary?["a"] = 1
    }
    #expect(box.wrappedValue == ["a": 1])

    box.mutate { $0 = nil }
    #expect(box.wrappedValue == nil)
}

@Test(arguments: mechanisms)
func optionalDictionaryConcurrentNilTogglingNeverCrashes(mechanism: ThreadSafeMechanism) {
    let box = ThreadSafe<[String: Int]?>(wrappedValue: nil, mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 16) { i in
        if i % 2 == 0 {
            for j in 0..<500 {
                box.mutate { $0 = j.isMultiple(of: 2) ? nil : ["k": j] }
            }
        } else {
            for _ in 0..<500 {
                _ = box.wrappedValue
            }
        }
    }
}

// MARK: - Array of optionals: ThreadSafe<[Int?]>
// A non-optional array of optionals gets the full array API.

@Test(arguments: mechanisms)
func arrayOfOptionalsSupportsNilElements(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe<[Int?]>(mechanism: mechanism)
    array.append(1)
    array.append(nil)
    array.append(3)
    #expect(array.elements == [1, nil, 3])
    #expect(array[1] == nil)
    #expect(array.popLast() == 3)
    #expect(array.count == 2)
}

@Test(arguments: mechanisms)
func arrayOfOptionalsConcurrentAppendIncludingNilNeverCrashes(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe<[Int?]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 500) { i in
        array.append(i.isMultiple(of: 2) ? nil : i)
    }
    #expect(array.count == 500)
    #expect(array.elements.filter { $0 == nil }.count == 250)
}

// MARK: - Dictionary of optional values: ThreadSafe<[String: Int?]>
// `Int?` values make the subscript take `Int??`, so absent and present-nil keys must both work.

@Test(arguments: mechanisms)
func dictionaryOfOptionalValuesDistinguishesAbsentFromPresentNil(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe<[String: Int?]>(mechanism: mechanism)

    // Present, with a real value.
    dictionary["a"] = 1
    #expect(dictionary["a"] == .some(1))
    #expect(dictionary.count == 1)

    // Present, but the value itself is nil — note the explicit double-wrap.
    dictionary["b"] = Int?.none
    #expect(dictionary.count == 2)
    #expect(dictionary["b"] == .some(nil))

    // Absent entirely — removes the key.
    dictionary["a"] = nil
    #expect(dictionary.count == 1)
    #expect(dictionary["a"] == nil)
}

@Test(arguments: mechanisms)
func dictionaryOfOptionalValuesConcurrentMutationNeverCrashes(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe<[Int: Int?]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 500) { i in
        dictionary[i] = i.isMultiple(of: 2) ? Int?.none : i
    }
    #expect(dictionary.count == 500)
}
