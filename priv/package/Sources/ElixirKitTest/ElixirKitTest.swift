//
//  ElixirKitTest.swift
//  ElixirKit
//
//  Created by Carson.Katri on 3/18/25.
//

import Testing
@testable import ElixirKit

@Test func testElixirKit() async {
    ElixirKit.start()
    try! await Task.sleep(for: .seconds(5)) // wait for elixir to finish executing
}
