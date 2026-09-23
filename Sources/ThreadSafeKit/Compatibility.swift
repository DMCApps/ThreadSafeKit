/// Legacy spelling of ``ThreadSafe``, kept as a permanently supported alias — not deprecated.
public typealias ThreadSafeAtomic<Value: Sendable> = ThreadSafe<Value>

/// Legacy spelling of ``ThreadSafe`` for the array shape, kept as a permanently supported alias — not
/// deprecated. Array-specific members (`append`/`push`/`pop`/etc.) come from the constrained extensions
/// in `ThreadSafe+Array.swift` and `ThreadSafe+Collection.swift`.
public typealias ThreadSafeArray<Element: Sendable> = ThreadSafe<[Element]>

/// Legacy spelling of ``ThreadSafe`` for the dictionary shape, kept as a permanently supported alias —
/// not deprecated. Dictionary-specific members (`getValue`/`setValue`/etc.) come from the constrained
/// extension in `ThreadSafe+Dictionary.swift`.
public typealias ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable> = ThreadSafe<[Key: Value]>
