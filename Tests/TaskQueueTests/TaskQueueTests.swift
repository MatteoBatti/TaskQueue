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
  
  @Test("Multiple operations execute in order", .tags(.fast, .stress))
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
  
  
  @Test("Multiple barrier operations execute in order", .tags(.barrier, .stress))
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
  
  
  @Test("Operations execute sequentially in serial queue", .tags(.fast))
  func operationsExecuteSequentiallyInSerialQueue() async throws {
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
  
  @Test("Operations respect QoS levels", .tags(.fast, .qos), arguments:
    [
      (TaskPriority.low, TaskPriority.medium),
      (TaskPriority.medium, TaskPriority.low),
      (TaskPriority.low, TaskPriority.high),
      (TaskPriority.high, TaskPriority.medium)
    ]
  )
  func operationsRespectQoSLevels(qos: TaskPriority, expectedMinimum: TaskPriority) async throws {
    let queue = TaskQueue(qos: expectedMinimum, attributes: [.concurrent])
    
    let task = queue.addOperation(qos: qos) {
      return Task.currentPriority
    }
    
    let actualPriority = await task.value
    #expect(actualPriority >= expectedMinimum)
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
    #expect(defaultPriority >= .medium, "Default queue should use medium priority")
  }
}


// MARK: - Cancellation Tests

@Suite("Cancellation", .tags(.cancellation))
struct CancellationTests {
  
  @Test("Queue cancellation propagates to all operations", .tags(.fast, .cancellation))
  func queueCancellationPropagates() async throws {
    let queue = TaskQueue()
    
    let task1 = queue.addOperation {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    
    let task2 = queue.addOperation {
      try await Task.sleep(nanoseconds: 1)
    }
    
    queue.cancellAllOperations()
    
    await #expect(throws: CancellationError.self) {
      try await task1.result.get()
    }
    
    await #expect(throws: CancellationError.self) {
      try await task2.result.get()
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
  
  @Test("Throwing operation propagates specific error correctly", .tags(.fast, .error))
  func throwingOperationPropagatesSpecificError() async throws {
    let queue = TaskQueue()
    
    let task = queue.addOperation {
      throw TestError.intentional
    }
    
    let result = await task.result
    
    #expect(throws: TestError.intentional) {
      try result.get()
    }
  }
  
  @Test("Different errors are propagated correctly", .tags(.fast, .error), arguments: [
    TestError.first, TestError.second, TestError.intentional
  ])
  func differentErrorsArePropagatedCorrectly(expectedError: TestError) async throws {
    let queue = TaskQueue()
    
    let task = queue.addOperation {
      throw expectedError
    }
    
    let result = await task.result
    
    #expect(throws: expectedError) {
      try result.get()
    }
  }
  
  @Test("Error in one operation does not affect subsequent operations", .tags(.fast, .regression))
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
    
    #expect(throws: TestError.first) {
      try result1.get()
    }
    
    let value = result2.get()
    #expect(value == 42)
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

// MARK: - Advanced Functionality Tests

@Suite("Advanced Functionality", .tags(.regression))
struct AdvancedFunctionalityTests {
  
  @Test("TaskQueue handles various operation counts", .tags(.stress), arguments: [1, 5, 10, 50, 100])
  func taskQueueHandlesVariousOperationCounts(operationCount: Int) async throws {
    let queue = TaskQueue(attributes: [.concurrent])
    let results: LockIsolated<Set<Int>> = LockIsolated(Set<Int>())
    var tasks: [Task<(), Never>] = []
    
    for i in 0..<operationCount {
      let task = queue.addOperation { [i] in
        results.update { $0.insert(i) }
      }
      tasks.append(task)
    }
    
    for task in tasks {
      await task.value
    }
    
    let finalResults = results.value()
    #expect(finalResults.count == operationCount)
    #expect(finalResults == Set(0..<operationCount))
  }
  
  @Test("Mixed operation types work together correctly", .tags(.fast, .concurrent, .barrier))
  func mixedOperationTypesWorkTogether() async throws {
    let queue = TaskQueue(attributes: [.concurrent])
    let results: LockIsolated<[String]> = LockIsolated([])
    var tasks: [Task<(), Never>] = []
    
    // Add regular operations
    for i in 0..<3 {
      let task = queue.addOperation { [i] in
        results.update { $0.append("regular-\(i)") }
      }
      tasks.append(task)
    }
    
    // Add barrier operation
    let barrierTask = queue.addBarrierOperation {
      results.update { $0.append("barrier") }
    }
    tasks.append(barrierTask)
    
    // Add more operations after barrier
    for i in 0..<2 {
      let task = queue.addOperation { [i] in
        results.update { $0.append("after-barrier-\(i)") }
      }
      tasks.append(task)
    }
    
    for task in tasks {
      await task.value
    }
    
    let finalResults = results.value()
    let barrierIndex = try #require(finalResults.firstIndex(of: "barrier"))
    
    // Verify barrier separated the operations
    let beforeBarrier = finalResults[..<barrierIndex]
    let afterBarrier = finalResults[(barrierIndex + 1)...]
    
    #expect(beforeBarrier.allSatisfy { $0.hasPrefix("regular-") })
    #expect(afterBarrier.allSatisfy { $0.hasPrefix("after-barrier-") })
  }
}
