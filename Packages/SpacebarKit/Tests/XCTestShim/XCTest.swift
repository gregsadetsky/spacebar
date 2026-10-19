// minimal XCTest look-alike so `make test` works with command line tools only
// (no xcode => no XCTest). used only when SPACEBAR_XCTEST_SHIM=1; CI with
// xcode builds the same tests against the real XCTest.
@_exported import Foundation

public struct ShimFailure {
    public let message: String
    public let file: StaticString
    public let line: UInt
}

public enum ShimState {
    nonisolated(unsafe) public static var failures: [ShimFailure] = []
    public static func record(_ message: String, file: StaticString, line: UInt) {
        failures.append(ShimFailure(message: message, file: file, line: line))
    }
}

@objcMembers open class XCTestCase: NSObject {
    public override required init() { super.init() }
    open func setUp() {}
    open func tearDown() {}
    open func setUpWithError() throws {}
    open func tearDownWithError() throws {}
}

private func describe(_ v: Any) -> String { String(describing: v) }

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    ShimState.record("XCTFail: \(message)", file: file, line: line)
}

public func XCTAssert(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(try expression(), message(), file: file, line: line)
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !expression() { ShimState.record("XCTAssertTrue failed. \(message())", file: file, line: line) } }
    catch { ShimState.record("XCTAssertTrue threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try expression() { ShimState.record("XCTAssertFalse failed. \(message())", file: file, line: line) } }
    catch { ShimState.record("XCTAssertFalse threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T?, _ b: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let x = try a(), y = try b()
        if x != y { ShimState.record("XCTAssertEqual failed: (\(describe(x as Any))) is not equal to (\(describe(y as Any))). \(message())", file: file, line: line) }
    } catch { ShimState.record("XCTAssertEqual threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T?, _ b: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let x = try a(), y = try b()
        if x == y { ShimState.record("XCTAssertNotEqual failed: (\(describe(x as Any))) is equal to (\(describe(y as Any))). \(message())", file: file, line: line) }
    } catch { ShimState.record("XCTAssertNotEqual threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let x = try a(), y = try b(); if !(x > y) { ShimState.record("XCTAssertGreaterThan failed: \(x) is not greater than \(y). \(message())", file: file, line: line) } }
    catch { ShimState.record("XCTAssertGreaterThan threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let x = try a(), y = try b(); if !(x < y) { ShimState.record("XCTAssertLessThan failed: \(x) is not less than \(y). \(message())", file: file, line: line) } }
    catch { ShimState.record("XCTAssertLessThan threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if let v = try expression() { ShimState.record("XCTAssertNil failed: \(describe(v)). \(message())", file: file, line: line) } }
    catch { ShimState.record("XCTAssertNil threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try expression() == nil { ShimState.record("XCTAssertNotNil failed. \(message())", file: file, line: line) } }
    catch { ShimState.record("XCTAssertNotNil threw \(error). \(message())", file: file, line: line) }
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ errorHandler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); ShimState.record("XCTAssertThrowsError failed: did not throw. \(message())", file: file, line: line) }
    catch { errorHandler(error) }
}

public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() } catch { ShimState.record("XCTAssertNoThrow failed: threw \(error). \(message())", file: file, line: line) }
}

public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    if let v = try expression() { return v }
    ShimState.record("XCTUnwrap failed: nil. \(message())", file: file, line: line)
    throw UnwrapFailure()
}

public struct UnwrapFailure: Error {}

/// discovers every XCTestCase subclass in the process and runs its test* methods
public enum ShimRunner {
    public static func runAll() -> Int32 {
        var count = objc_getClassList(nil, 0)
        let buffer = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(count))
        defer { buffer.deallocate() }
        let autoreleasing = AutoreleasingUnsafeMutablePointer<AnyClass>(buffer)
        count = objc_getClassList(autoreleasing, count)
        var classes: [XCTestCase.Type] = []
        for i in 0..<Int(count) {
            guard let cls = buffer[i], class_getSuperclass(cls) != nil else { continue }
            var sup: AnyClass? = cls
            var isCase = false
            while let s = sup, s != XCTestCase.self { sup = class_getSuperclass(s); if sup == XCTestCase.self { isCase = true } }
            if isCase, let t = cls as? XCTestCase.Type { classes.append(t) }
        }
        classes.sort { NSStringFromClass($0) < NSStringFromClass($1) }

        var total = 0, failed = 0
        for cls in classes {
            var methodCount: UInt32 = 0
            guard let methods = class_copyMethodList(cls, &methodCount) else { continue }
            defer { free(methods) }
            var names: [(String, Selector, Bool)] = []
            for i in 0..<Int(methodCount) {
                let sel = method_getName(methods[i])
                let name = NSStringFromSelector(sel)
                let encoding = method_getTypeEncoding(methods[i]).map { String(cString: $0) } ?? ""
                if name.hasPrefix("test") && !name.contains(":") && encoding.hasPrefix("v") {
                    names.append((name, sel, false))
                } else if name.hasPrefix("test") && name.hasSuffix("AndReturnError:") {
                    names.append((String(name.dropLast("AndReturnError:".count)), sel, true))
                }
            }
            names.sort { $0.0 < $1.0 }
            let className = NSStringFromClass(cls).split(separator: ".").last.map(String.init) ?? NSStringFromClass(cls)
            for (name, sel, throwing) in names {
                total += 1
                ShimState.failures = []
                let instance = cls.init()
                instance.setUp()
                do {
                    try instance.setUpWithError()
                    if throwing {
                        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
                        let imp = class_getMethodImplementation(cls, sel)!
                        let fn = unsafeBitCast(imp, to: Fn.self)
                        var err: NSError?
                        if !fn(instance, sel, &err) { throw err ?? NSError(domain: "shim", code: 1) }
                    } else {
                        _ = instance.perform(sel)
                    }
                    try instance.tearDownWithError()
                } catch {
                    ShimState.record("threw \(error)", file: #filePath, line: #line)
                }
                instance.tearDown()
                if ShimState.failures.isEmpty {
                    print("ok   \(className).\(name)")
                } else {
                    failed += 1
                    print("FAIL \(className).\(name)")
                    for f in ShimState.failures { print("     \(f.file):\(f.line): \(f.message)") }
                }
            }
        }
        print("\n\(total) tests, \(failed) failed")
        return failed == 0 && total > 0 ? 0 : 1
    }
}
