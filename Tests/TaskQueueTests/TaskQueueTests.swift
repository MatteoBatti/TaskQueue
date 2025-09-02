import Testing
import Foundation
@testable import TaskQueue

// MARK: - Serial Queue Tests

@Suite("Serial TaskQueue", .tags(.serial))
struct SerialTaskQueueTests {
    
    @Test("Single operation returns expected result", .tags(.fast))
    func singleOperation() async throws {
        let queue = TaskQueue()
        
        let task = queue.addOperation {
            return true
        }
        
        let result = await task.value
        #expect(result == true)
    }
    
    @Test("Multiple operations execute in order", .tags(.fast))
    func multipleOperationsInOrder() async throws {
        let queue = TaskQueue()
        var tasks: [Task<Int, Never>] = []
        
        for count in 1..<100 {
            let task = queue.addOperation {
                return count
            }
            tasks.append(task)
        }
        
        var results: [Int] = []
        for task in tasks {
            results.append(await task.value)
        }
        
        #expect(results == results.sorted())
    }
    
    @Test("Multiple barrier operations execute in order", .tags(.barrier))
    func multipleBarrierOperationsInOrder() async throws {
        let queue = TaskQueue()
        var tasks: [Task<Int, Never>] = []
        
        for count in 1..<100 {
            let task = queue.addBarrierOperation {
                return count
            }
            tasks.append(task)
        }
        
        var results: [Int] = []
        for task in tasks {
            results.append(await task.value)
        }
        
        #expect(results == results.sorted())
    }
    
    @Test("Second operation waits for the first one", .tags(.fast))
    func secondOperationWaitsForFirst() async throws {
        let queue = TaskQueue()
        let results: LockIsolated<[Int]> = LockIsolated([])
        var tasks: [Task<(), Never>] = []
        
        let task1 = queue.addOperation {
            try? await Task.sleep(nanoseconds: 1_000_000)
            results.update {
                $0.append(1)
            }
        }
        tasks.append(task1)
        
        let task2 = queue.addOperation {
            results.update {
                $0.append(2)
            }
        }
        tasks.append(task2)
        
        for task in tasks {
            await task.value
        }
        
        #expect(results.value() == [1, 2])
    }
    
    @Test("First operation as barrier executes before subsequent operations", .tags(.barrier))
    func firstOperationAsBarrier() async throws {
        let queue = TaskQueue()
        let results: LockIsolated<[Int]> = LockIsolated([])
        var tasks: [Task<(), Never>] = []
        
        let task1 = queue.addBarrierOperation {
            try? await Task.sleep(nanoseconds: 1_000_000)
            results.update {
                $0.append(1)
            }
        }
        tasks.append(task1)
        
        let task2 = queue.addOperation {
            results.update {
                $0.append(2)
            }
        }
        tasks.append(task2)
        
        for task in tasks {
            await task.value
        }
        
        #expect(results.value() == [1, 2])
    }
}

// MARK: - Concurrent Queue Tests

@Suite("Concurrent TaskQueue", .tags(.concurrent))
struct ConcurrentTaskQueueTests {
    
    @Test("Multiple operations can execute concurrently", .tags(.fast))
    func multipleOperationsConcurrently() async throws {
        let queue = TaskQueue(attributes: [.concurrent])
        let results: LockIsolated<[Int]> = LockIsolated([])
        var tasks: [Task<(), Never>] = []
        
        let task1 = queue.addOperation {
            try? await Task.sleep(nanoseconds: 1_000_000)
            results.update {
                $0.append(1)
            }
        }
        tasks.append(task1)
        
        let task2 = queue.addOperation {
            results.update {
                $0.append(2)
            }
        }
        tasks.append(task2)
        
        for task in tasks {
            await task.value
        }
        
        #expect(results.value() == [2, 1])
    }
    
    @Test("First operation as barrier blocks concurrent execution", .tags(.barrier))
    func firstOperationAsBarrierBlocksConcurrentExecution() async throws {
        let queue = TaskQueue(attributes: [.concurrent])
        let results: LockIsolated<[Int]> = LockIsolated([])
        var tasks: [Task<(), Never>] = []
        
        let task1 = queue.addBarrierOperation {
            try? await Task.sleep(nanoseconds: 1_000_000)
            results.update {
                $0.append(1)
            }
        }
        tasks.append(task1)
        
        let task2 = queue.addOperation {
            results.update {
                $0.append(2)
            }
        }
        tasks.append(task2)
        
        for task in tasks {
            await task.value
        }
        
        #expect(results.value() == [1, 2])
    }

    @Test("Barrier operation in middle ensures correct execution order", .tags(.barrier))
    func barrierOperationInMiddle() async throws {
        let queue = TaskQueue(attributes: [.concurrent])
        let results: LockIsolated<[Int]> = LockIsolated([])
        var tasks: [Task<(), Never>] = []
        
        for idx in 0...10 {
            let task = queue.addOperation { [idx] in
                results.update {
                    $0.append(idx)
                }
            }
            tasks.append(task)
        }
        
        let barrierTask = queue.addBarrierOperation {
            results.update {
                $0.append(11)
            }
        }
        tasks.append(barrierTask)
        
        let finalTask = queue.addOperation {
            results.update {
                $0.append(12)
            }
        }
        tasks.append(finalTask)
        
        for task in tasks {
            await task.value
        }
        
        #expect(results.value().last == 12)
    }
    
    @Test("Barrier isolates operations before and after", .tags(.barrier))
    func barrierIsolatesOperations() async throws {
        let queue = TaskQueue(attributes: [.concurrent])
        let results: LockIsolated<[String]> = LockIsolated([])
        var tasks: [Task<(), Never>] = []
        
        let beforeBarrier1 = queue.addOperation {
            try? await Task.sleep(nanoseconds: 2_000_000)
            results.update { $0.append("before1") }
        }
        tasks.append(beforeBarrier1)
        
        let beforeBarrier2 = queue.addOperation {
            results.update { $0.append("before2") }
        }
        tasks.append(beforeBarrier2)
        
        let barrier = queue.addBarrierOperation {
            results.update { $0.append("barrier") }
        }
        tasks.append(barrier)
        
        let afterBarrier1 = queue.addOperation {
            results.update { $0.append("after1") }
        }
        tasks.append(afterBarrier1)
        
        let afterBarrier2 = queue.addOperation {
            results.update { $0.append("after2") }
        }
        tasks.append(afterBarrier2)
        
        for task in tasks {
            await task.value
        }
        
        let finalResults = results.value()
        let barrierIndex = try #require(finalResults.firstIndex(of: "barrier"))
        
        #expect(barrierIndex > 0)
        #expect(barrierIndex < finalResults.count - 1)
        
        let beforeBarrierResults = Array(finalResults[..<barrierIndex])
        let afterBarrierResults = Array(finalResults[(barrierIndex + 1)...])
        
        #expect(beforeBarrierResults.contains("before1"))
        #expect(beforeBarrierResults.contains("before2"))
        #expect(afterBarrierResults.contains("after1"))
        #expect(afterBarrierResults.contains("after2"))
    }
}

// MARK: - Quality of Service Tests

@Suite("Quality of Service", .tags(.qos))
struct QualityOfServiceTests {
    
    @Test("Operations respect different QoS levels", .tags(.fast))
    func operationsRespectQoSLevels() async throws {
        let queue = TaskQueue(attributes: [.concurrent])
        var tasks: [Task<(), Never>] = []
        
        tasks.append(
            queue.addOperation(qos: .medium) {
                #expect(Task.currentPriority == .medium)
                return
            }
        )
        
        tasks.append(
            queue.addOperation(qos: .low) {
                #expect(Task.currentPriority >= .low)
                return
            }
        )
        
        tasks.append(
            queue.addOperation(qos: .high) {
                #expect(Task.currentPriority >= .high)
                return
            }
        )
        
        for task in tasks {
            await task.value
        }
    }
    
    @Test("Queue respects default QoS when none specified", .tags(.fast))
    func defaultQoSBehavior() async throws {
        let defaultQueue = TaskQueue()
        let highPriorityQueue = TaskQueue(qos: .high)
        
        let defaultTask = defaultQueue.addOperation {
            // Should use system default priority
            return Task.currentPriority
        }
        
        let highPriorityTask = highPriorityQueue.addOperation {
            return Task.currentPriority
        }
        
        let defaultPriority = await defaultTask.value
        let highPriority = await highPriorityTask.value
        
        #expect(highPriority >= .high, "High priority queue should use high priority")
        #expect(defaultPriority != nil, "Default queue should have some priority")
    }
}


// MARK: - Cancellation Tests

@Suite("Cancellation", .tags(.cancellation))
struct CancellationTests {
    
    @Test("Queue cancellation propagates to all operations", .tags(.fast))
    func queueCancellationPropagates() async throws {
        let queue = TaskQueue()
        
        let task1 = queue.addOperation {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        let task2 = queue.addOperation {
            try await Task.sleep(nanoseconds: 1)
        }
        
        queue.cancellAllOperations()
        
        do {
            try await task1.result.get()
            Issue.record("Task1 should have been cancelled")
        } catch {
            #expect(error is CancellationError)
        }
        
        do {
            try await task2.result.get()
            Issue.record("Task2 should have been cancelled")
        } catch {
            #expect(error is CancellationError)
        }
    }
}

// MARK: - Error Handling Tests

@Suite("Error Handling", .tags(.error))
struct ErrorHandlingTests {
    
    enum TestError: Error {
        case intentional
        case first
        case second
    }
    
    @Test("Throwing operation propagates error correctly", .tags(.fast))
    func throwingOperationPropagatesError() async throws {
        let queue = TaskQueue()
        
        let task = queue.addOperation {
            throw TestError.intentional
        }
        
        let result = await task.result
        
        #expect(throws: TestError.self) {
            try result.get()
        }
    }
    
    @Test("Error in one operation does not affect subsequent operations", .tags(.fast))
    func errorDoesNotAffectSubsequentOperations() async throws {
        let queue = TaskQueue()
        
        let task1 = queue.addOperation {
            throw TestError.first
        }
        
        let task2 = queue.addOperation {
            return 42
        }
        
        let result1 = await task1.result
        let result2 = await task2.result
        
        #expect(throws: TestError.self) {
            try result1.get()
        }
        
        switch result2 {
        case .success(let value):
            #expect(value == 42)
        case .failure:
            Issue.record("Task2 should not have failed")
        }
    }
}

// MARK: - Basic Functionality Tests

@Suite("Basic Functionality", .tags(.fast))
struct BasicFunctionalityTests {
    
    @Test("Empty queue can be created")
    func emptyQueueCreation() async throws {
        let queue = TaskQueue()
        // Queue should be successfully created with default attributes
        #expect(queue.attributes.rawValue == 0)
    }
    
    @Test("Single barrier operation executes successfully")
    func singleBarrierOperation() async throws {
        let queue = TaskQueue(attributes: [.concurrent])
        
        let task = queue.addBarrierOperation {
            return 42
        }
        
        let result = await task.value
        #expect(result == 42)
    }
    
    @Test("Barrier in concurrent queue separates operation groups", .tags(.barrier, .concurrent))
    func barrierSeparatesOperationGroups() async throws {
        let queue = TaskQueue(attributes: [.concurrent])
        let results: LockIsolated<[Int]> = LockIsolated([])
        var tasks: [Task<(), Never>] = []
        
        for idx in 1...3 {
            let task = queue.addOperation { [idx] in
                try? await Task.sleep(nanoseconds: 1_000_000)
                results.update { $0.append(idx) }
            }
            tasks.append(task)
        }
        
        let barrierTask = queue.addBarrierOperation {
            results.update { $0.append(99) }
        }
        tasks.append(barrierTask)
        
        for idx in 4...6 {
            let task = queue.addOperation { [idx] in
                results.update { $0.append(idx) }
            }
            tasks.append(task)
        }
        
        for task in tasks {
            await task.value
        }
        
        let finalResults = results.value()
        let barrierIndex = try #require(finalResults.firstIndex(of: 99))
        let beforeBarrier = finalResults[..<barrierIndex]
        let afterBarrier = finalResults[(barrierIndex + 1)...]
        
        #expect(beforeBarrier.contains(1) && beforeBarrier.contains(2) && beforeBarrier.contains(3))
        #expect(afterBarrier.contains(4) && afterBarrier.contains(5) && afterBarrier.contains(6))
    }
}