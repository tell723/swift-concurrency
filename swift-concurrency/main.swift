//
//  main.swift
//  
//  
//  Created by Terumu Watanabe on 2024/11/10
//  
//

import Foundation
import SwiftUI

///  実行時に起こるスレッドの問題を型で解決



/// メインスレッド（Main Actor）で実行のため、Task に渡すクロージャも Main Actor が引き継がれる
/// Task 内部で non-Sendable をキャプチャしても同じ Isolation domain なので安全

/// ```swift
//final class Box {
//    var value: Int = 0
//}
//let box: Box = .init()
//
//MainActor.assertIsolated()
//
//Task {
//    // Main Actor
//    box.value = -1 // エラーは出ない
//}
//
//Task {
//    // Main Actor
//    print(box.value)
//}
/// ```




/// Main Actor が引き継がれないため、non-Sendable へのアクセスはエラーになる

//final class Box {
//    var value: Int = 0
//}
//
//func run() {
//    let box: Box = .init()
//    Task {
//        // ERROR: Capture of 'box' with non-sendable type 'Box' in a `@Sendable` closure
//        box.value = -1
//    }
//
//    Task {
//        // ERROR: Capture of 'box' with non-sendable type 'Box' in a `@Sendable` closure
//        print(box.value)
//    }
//}



/// Box 型が Sendable のため、box は Isolation boundary を超えられる

//final class Box: Sendable {
//    let value: Int = 0 // let に変更
//}
//
//func run() {
//    let box: Box = .init()
//    Task {
//        print(box.value)
//    }
//
//    Task {
//        print(box.value)
//    }
//}



/// non-Sendable が actor の Isolation domain を超えようとする例
/// 異なる Isolation domain のため、 box を渡すとエラーになる

//final class Box {
//    let value: Int = 0 // let に変更
//}
//
//actor A {
//    var box: Box?
//    func setBox(_ box: Box) {
//        self.box = box
//    }
//
//    func foo() {}
//}
//
//func run() async {
//    let box: Box = .init()
//    let a: A = .init()
//
//    // ERROR: Passing argument of non-sendable type 'Box' into actor-isolated context may introduce data races
//    await a.setBox(box)
//    await a.foo()
//}



/// 関数の Sendable化
/// 関数は Sendable プロトコルに準拠できない代わりに `@Sendable` で Sendable になることができる
/// Isolation border を超えられる
/**
 ```
final class Box {
    let value: Int = 0 // let に変更
}

actor A {
    var box: Box?
    func setBox(_ box: Box) {
        self.box = box
    }

    func foo() {}
    func useF(_ f: @escaping () -> Void) {}
}

func run() async {
    let box: Box = .init()
    let a: A = .init()
    let f: @Sendable () -> Void = {}
    await a.useF(f)
}
 ```
*/




/// MainActor から non-isolated な処理（state.load）に non-Sendable を渡すとエラーになる

struct User: Sendable, Identifiable {
    var id: String
    var name: String
    // ...
}

// Xcode 16~ では View 全体が MainActor になるのでアノテーション不要
@MainActor
struct UserListView: View {
    @State private var state: UserListViewState = .init()

    var body: some View {
        List(state.users) { user in
            NavigationLink {
            } label: {
                Text(user.name)
            }
            .task {
                await state.load()
                // Error: Sending 'self.state' risks causing data races
                ///Sending main actor-isolated 'self.state' to nonisolated instance method 'load()' risks causing data races between nonisolated and main actor-isolated uses
                // state.load() は load(self: state) とも捉えられるため、state を渡していることになる
                // UseListViewState は non-Sendable なため、non-Isolated 関数（load()）に渡すことができない
            }
        }
    }
}


@Observable
final class UserListViewState: Sendable {
    private(set) var users: [User] = []

    func foo(x: Int) {}

    func  load() async {
        do {
            users = try await UserRepository.fetchAllValues()
        } catch {
        }
    }
}


enum UserRepository {
    static func fetchAllValues() async throws -> [User] {
        [] // TODO
    }
}



/// Task は Global Actor の場合は Isolation domain を引き継ぐが、 通常の Actor の場合は必ずしもそうではない
/// もし Task クロージャで self をキャプチャしていれば、Isolation domain を引き継ぐようになる
/// 以下のプロポーサルで解消予定
/// https://github.com/sophiapoirier/swift-evolution/blob/closure-isolation/proposals/nnnn-closure-isolation-control.md
//final class Box {
//    var value: Int = 0
//}


//actor A {
//    var box: Box?
//    func setBox(_ box: Box) {
//        self.box = box
//    }

    /// ここで @MainActor を付与すると、Task は MainActor を引き継ぐためエラーにならない
//    func foo() {
//        let box: Box = .init()
//        Task {
//             _ = self   // <- これで actor の Isolation domain を引き継ぐため、エラーは出ない
            // ERROR: Capture of 'box' with non-sendable type 'Box' in a `@Sendable` closure
//            box.value -= 1
//        }
//        print(box.value)
//    }
//    func useF(_ f: @escaping () -> Void) {}
//}
//
//func run() async {
//    let box: Box = .init()
//    let a: A = .init()
//    let f: @Sendable () -> Void = {}
//    await a.useF(f)
//}




final class Box {
    var value: Int = 0
}


actor A {
    var box: Box?
    func setBox(_ box: Box) {
        self.box = box
    }

//     ここで @MainActor を付与すると、Task は MainActor を引き継ぐためエラーにならない
    func foo() {
//        let box: Box = .init()
        Task {
//             _ = self   // <- これで actor の Isolation domain を引き継ぐため、エラーは出ない
                    let b: Box = .init()
//             ERROR: Capture of 'box' with non-sendable type 'Box' in a `@Sendable` closure
            box = b
        }
//        print(box.value)
    }
    func useF(_ f: @escaping () -> Void) {}
}

func run() async {
    let box: Box = .init()
    let a: A = .init()
    let f: @Sendable () -> Void = {}
    await a.useF(f)
}




/// region based isolation
/// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md
/// non-Senable なデータが isolation boundary を超えるケース
/// non-Senable な型が isolation boundary を超えたとしても、その後に non-Sendable な型を使うことがなければ安全とみなされ、エラーにならない
/// 関数内で初期化されたものか、 sending 引数の必要がある
/// ＊現状正しく動作していないようなので、過信はNG

//final class Box {
//    var value: Int = 0
//}
//
//actor A {
//    var box: Box?
//    func setBox(_ box: Box) {
//        self.box = box
//    }
//}
//
//@MainActor
//func run() async {
//    let box: Box = .init()
//    let a: A = .init()
//    await a.setBox(box) // ここが最後の box へのアクセスになっていれば問題ない
////    print(box.value)
//}




/// isolated 引数
/// 関数にactor 型を isolated 引数を定義すると、関数はその actor の isolation domain で処理される
/// isolated 引数は1つしか定義することができない
/// actor 型のメソッド引数に別の actor を isolated 引数を与えると、別の actor の isolation domain で処理される
/// actor メソッドは全て暗黙的に `isolated: self`  のような引数を定義している
///
//final class Box {
//    var value: Int = 0
//}
//
//actor A {
//    var box: Box?
//    func setBox(_ box: Box) {
//        self.box = box
//    }
//}
//
//func run(a: isolated A) async {
//    let box: Box = .init()
//    a.setBox(box) // run() 内部は Actor A の isolation domain になるので await が不要
//}
