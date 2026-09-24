import Foundation
import Testing
@testable import ThreadSafeKit

// Coverage for Value == Optional<T> (both the wrapped value itself being optional, and
// collections whose element/keyed-value is optional). `storage: Value` is a plain, non-optional
// stored property (see ThreadSafe.swift), so there's no separate "is it populated" wrapper layer
// to get confused with the real, possibly-nil `Value` — this just verifies the wrapped nil itself
// is handled correctly end to end (init, mutate, read) across every mechanism.

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
    // Repeatedly flips between nil and a value while readers hammer `wrappedValue`. This is
    // exactly the shape that would force-unwrap-crash if `read`/`write` ever confused an
    // internal "populated" sentinel with the value's own nil.
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
// `Optional<[Int]>` is not itself a Collection, so this only gets the base row
// (wrappedValue/mutate/description) — no append/count/etc.

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
// Same story as the array: Optional<[Key: Value]> isn't itself keyed storage, so only the
// base row is available.

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
// The collection itself is non-optional, so the full array shape (append/pop/subscript/etc.)
// applies; the element type happens to be optional.

@Test(arguments: mechanisms)
func arrayOfOptionalsSupportsNilElements(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe<[Int?]>(mechanism: mechanism)
    array.append(1)
    array.append(nil)
    array.append(3)
    #expect(array.elements == [1, nil, 3])
    #expect(array[1] == nil)
    #expect(array.pop() == 3)
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
// Genuinely subtle: `Value.KeyedValue` is itself `Int?`, so `setValue`/the keyed subscript
// take `Int??` — a key can be ABSENT (removeValue / setValue(nil)) or PRESENT-with-a-nil-value
// (setValue(Int?.none)). These are different states; both must be reachable without crashing.

@Test(arguments: mechanisms)
func dictionaryOfOptionalValuesDistinguishesAbsentFromPresentNil(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe<[String: Int?]>(mechanism: mechanism)

    // Present, with a real value.
    dictionary.setValue(1, forKey: "a")
    #expect(dictionary.getValue(forKey: "a") == .some(1))
    #expect(dictionary.count == 1)

    // Present, but the value itself is nil — note the explicit double-wrap.
    dictionary.setValue(Int?.none, forKey: "b")
    #expect(dictionary.count == 2)
    #expect(dictionary.getValue(forKey: "b") == .some(nil))

    // Absent entirely — removes the key.
    dictionary.setValue(nil, forKey: "a")
    #expect(dictionary.count == 1)
    #expect(dictionary.getValue(forKey: "a") == nil)
}

@Test(arguments: mechanisms)
func dictionaryOfOptionalValuesConcurrentMutationNeverCrashes(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe<[Int: Int?]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 500) { i in
        dictionary.setValue(i.isMultiple(of: 2) ? Int?.none : i, forKey: i)
    }
    #expect(dictionary.count == 500)
}
