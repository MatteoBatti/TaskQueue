import Foundation

internal protocol Cancellable {
  func cancel()
  var isCancelled: Bool { get }
}

internal protocol Endable {
  func awaitToBeCompleted() async
}

internal typealias OperationTask = any (Cancellable & Endable)
public typealias AsyncThrowingOperation<Success> = @isolated(any) @Sendable () async throws -> sending Success
public typealias AsyncOperation<Success> = @isolated(any) @Sendable () async -> sending Success

/// A thread-safe task queue that manages the execution order of asynchronous operations.
///
/// TaskQueue provides a way to control the execution order of async operations, supporting both
/// serial and concurrent execution modes. It also supports barrier operations that ensure
/// proper synchronization points in concurrent queues.
///
/// ## Usage
///
/// ```swift
/// // Serial queue (default)
/// let serialQueue = TaskQueue()
/// 
/// // Concurrent queue
/// let concurrentQueue = TaskQueue(attributes: [.concurrent])
/// 
/// // Queue with custom QoS
/// let highPriorityQueue = TaskQueue(qos: .high)
/// ```
final public class TaskQueue: @unchecked Sendable {
  
  /// Configuration attributes for the TaskQueue.
  public struct Attributes: OptionSet, Sendable {
    public let rawValue: UInt64
    
    /// Enables concurrent execution of operations.
    /// When set, operations can run in parallel unless separated by barrier operations.
    public static let concurrent = Attributes(rawValue: 1 << 0)
    
    /// Creates an attributes set with the specified raw value.
    /// - Parameter rawValue: The raw value for the attributes.
    public init(rawValue: UInt64) {
      self.rawValue = rawValue
    }
  }
  
  internal struct Operation: Identifiable {
    let id: UUID
    let task: OperationTask
    let isBarrier: Bool
  }
  
  private var operations: [Operation] = []
  private let lock: NSRecursiveLock = NSRecursiveLock()
  
  let defaultQos: TaskPriority?
  let attributes: Attributes
  
  /// Creates a new TaskQueue with the specified configuration.
  ///
  /// - Parameters:
  ///   - qos: The default quality of service (priority) for operations added to this queue.
  ///          If not specified, operations will use the system default priority.
  ///   - attributes: Configuration attributes for the queue. Use `.concurrent` for parallel execution.
  ///                 Defaults to serial execution.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// // Serial queue with default priority
  /// let queue = TaskQueue()
  ///
  /// // Concurrent queue with high priority
  /// let fastQueue = TaskQueue(qos: .high, attributes: [.concurrent])
  ///
  /// // Serial queue with user-initiated priority  
  /// let uiQueue = TaskQueue(qos: .userInitiated)
  /// ```
  public init(qos: TaskPriority? = nil, attributes: Attributes = []) {
    self.defaultQos = qos
    self.attributes = attributes
  }
  
  private func appendAsyncThrowingOperation<Success>(
    @_inheritActorContext _ operation: @escaping AsyncThrowingOperation<Success>,
    qos: TaskPriority?,
    isBarrier: Bool
  ) -> Task<Success, Error>{
    lock.lock()
    defer {
      lock.unlock()
    }

    let id = UUID()
    let previousOperations = self.previousOperationsToWaitFor(isCurrentOperationABarrier: isBarrier)
    let task = Task(priority: qos ?? defaultQos) { [previousOperations] in
      defer {
        self.removeCompletedOperation(id)
      }
      for operation in previousOperations {
        await operation.task.awaitToBeCompleted()
      }
      return try await operation()
    }
    
    operations.append(Operation(id: id, task: task, isBarrier: isBarrier))
    return task
  }
  
  private func appendAsyncOperation<Success>(
    @_inheritActorContext _ operation: @escaping AsyncOperation<Success>,
    qos: TaskPriority?,
    isBarrier: Bool
  ) -> Task<Success, Never>{
    lock.lock()
    defer {
      lock.unlock()
    }

    let id = UUID()
    let previousOperations = self.previousOperationsToWaitFor(isCurrentOperationABarrier: isBarrier)
    let task = Task(priority: qos ?? defaultQos) { [previousOperations] in
      defer {
        self.removeCompletedOperation(id)
      }
      for operation in previousOperations {
        await operation.task.awaitToBeCompleted()
      }
      return await operation()
    }
    
    operations.append(Operation(id: id, task: task, isBarrier: isBarrier))
    return task
  }
  
  private func previousOperationsToWaitFor(isCurrentOperationABarrier isBarrier: Bool) -> [Operation] {
    let previousOperations: [Operation]
    let isConcurrent = attributes.contains(.concurrent)
    let lastOperationIndexToWaitFor: Int?
    if operations.count > 0 {
      lastOperationIndexToWaitFor = operations.lastIndex(where: { $0.isBarrier }) ?? (isBarrier ? operations.count - 1 : nil)
    } else {
      lastOperationIndexToWaitFor = nil
    }
    switch (isConcurrent, lastOperationIndexToWaitFor) {
    case (true, .none):
      previousOperations = []
      
    case (_, .some(let idx)):
      previousOperations = Array(operations[0...idx])
      
    case (false, .none):
      previousOperations = operations
    }
    return previousOperations
  }
  
  private func removeCompletedOperation(_ id: UUID) {
    lock.lock()
    defer {
      lock.unlock()
    }
    operations.removeAll { $0.id == id }
    
    // Remove all cancelled operations.
    operations.removeAll { operation in
      return operation.task.isCancelled
    }
  }
}

extension TaskQueue {
  
  /// Adds an operation that can throw errors to the queue.
  ///
  /// Operations are executed according to the queue's configuration:
  /// - In serial queues: operations execute one after another in FIFO order
  /// - In concurrent queues: operations can execute in parallel unless blocked by barriers
  ///
  /// - Parameters:
  ///   - qos: The quality of service for this specific operation. If nil, uses the queue's default QoS.
  ///   - operation: The async operation to execute. This closure inherits the caller's actor context.
  ///
  /// - Returns: A Task representing the operation. You can await its completion or handle its result/error.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// let queue = TaskQueue()
  ///
  /// // Add a simple operation
  /// let task = queue.addOperation {
  ///     try await someAsyncFunction()
  ///     return "completed"
  /// }
  ///
  /// // Handle the result
  /// do {
  ///     let result = try await task.value
  ///     print(result) // "completed"
  /// } catch {
  ///     print("Operation failed: \(error)")
  /// }
  /// ```
  @discardableResult
  public func addOperation<Success>(
    qos: TaskPriority? = nil,
    @_inheritActorContext _ operation: @escaping AsyncThrowingOperation<Success>
  ) -> Task<Success, Error> {
    return appendAsyncThrowingOperation(
      operation,
      qos: qos,
      isBarrier: false
    )
  }
  
  /// Adds an operation that cannot throw errors to the queue.
  ///
  /// Operations are executed according to the queue's configuration:
  /// - In serial queues: operations execute one after another in FIFO order  
  /// - In concurrent queues: operations can execute in parallel unless blocked by barriers
  ///
  /// - Parameters:
  ///   - qos: The quality of service for this specific operation. If nil, uses the queue's default QoS.
  ///   - operation: The async operation to execute. This closure inherits the caller's actor context.
  ///
  /// - Returns: A Task representing the operation. You can await its completion.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// let queue = TaskQueue()
  ///
  /// // Add a non-throwing operation
  /// let task = queue.addOperation {
  ///     await processData()
  ///     return 42
  /// }
  ///
  /// // Get the result (no error handling needed)
  /// let result = await task.value
  /// print(result) // 42
  /// ```
  @discardableResult
  public func addOperation<Success>(
    qos: TaskPriority? = nil,
    @_inheritActorContext _ operation: @escaping AsyncOperation<Success>
  ) -> Task<Success, Never> {
    return appendAsyncOperation(
      operation,
      qos: qos,
      isBarrier: false
    )
  }
}

extension TaskQueue {
  /// Adds a barrier operation that can throw errors to the queue.
  ///
  /// Barrier operations provide synchronization points in the queue:
  /// - All operations submitted before the barrier must complete before the barrier executes
  /// - All operations submitted after the barrier wait for the barrier to complete before executing
  /// - In concurrent queues, this effectively creates a serialization point
  ///
  /// - Parameters:
  ///   - qos: The quality of service for this specific operation. If nil, uses the queue's default QoS.
  ///   - operation: The async operation to execute. This closure inherits the caller's actor context.
  ///
  /// - Returns: A Task representing the barrier operation.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// let concurrentQueue = TaskQueue(attributes: [.concurrent])
  ///
  /// // These operations can run in parallel
  /// concurrentQueue.addOperation { await downloadFile1() }
  /// concurrentQueue.addOperation { await downloadFile2() }
  /// concurrentQueue.addOperation { await downloadFile3() }
  ///
  /// // This barrier waits for all downloads to complete
  /// concurrentQueue.addBarrierOperation {
  ///     print("All downloads completed")
  ///     try await processDownloadedFiles()
  /// }
  ///
  /// // These operations wait for the barrier to complete
  /// concurrentQueue.addOperation { await uploadResults() }
  /// ```
  public func addBarrierOperation<Success>(
    qos: TaskPriority? = nil,
    @_inheritActorContext _ operation: @escaping AsyncThrowingOperation<Success>
  ) -> Task<Success, Error> {
    return appendAsyncThrowingOperation(
      operation,
      qos: qos,
      isBarrier: true
    )
  }
  
  /// Adds a barrier operation that cannot throw errors to the queue.
  ///
  /// Barrier operations provide synchronization points in the queue:
  /// - All operations submitted before the barrier must complete before the barrier executes
  /// - All operations submitted after the barrier wait for the barrier to complete before executing  
  /// - In concurrent queues, this effectively creates a serialization point
  ///
  /// - Parameters:
  ///   - qos: The quality of service for this specific operation. If nil, uses the queue's default QoS.
  ///   - operation: The async operation to execute. This closure inherits the caller's actor context.
  ///
  /// - Returns: A Task representing the barrier operation.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// let concurrentQueue = TaskQueue(attributes: [.concurrent])
  ///
  /// // Parallel operations
  /// concurrentQueue.addOperation { await task1() }
  /// concurrentQueue.addOperation { await task2() }
  ///
  /// // Synchronization point
  /// concurrentQueue.addBarrierOperation {
  ///     await consolidateResults()
  ///     return "barrier complete"
  /// }
  ///
  /// // This waits for barrier
  /// concurrentQueue.addOperation { await finalTask() }
  /// ```
  public func addBarrierOperation<Success>(
    qos: TaskPriority? = nil,
    @_inheritActorContext _ operation: @escaping AsyncOperation<Success>
  ) -> Task<Success, Never> {
    return appendAsyncOperation(
      operation,
      qos: qos,
      isBarrier: true
    )
  }
}

extension TaskQueue {
  
  /// Cancels all currently queued operations and clears the queue.
  ///
  /// This method immediately cancels all pending operations in the queue and removes them.
  /// Operations that are already executing will receive a cancellation signal and should
  /// check for cancellation using `Task.checkCancellation()` or similar mechanisms.
  ///
  /// - Note: After calling this method, the queue is empty and ready to accept new operations.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// let queue = TaskQueue()
  ///
  /// // Add several operations
  /// queue.addOperation { await longRunningTask1() }
  /// queue.addOperation { await longRunningTask2() } 
  /// queue.addOperation { await longRunningTask3() }
  ///
  /// // Cancel everything
  /// queue.cancelAllOperations()
  ///
  /// // Queue is now empty and ready for new operations
  /// queue.addOperation { await newTask() }
  /// ```
  public func cancellAllOperations() {
    lock.lock()
    defer {
      lock.unlock()
    }
    
    for operation in operations {
      operation.task.cancel()
    }
    operations.removeAll()
  }
}

extension Task: Cancellable { }

extension Task: Endable {
  public func awaitToBeCompleted() async {
    _ = try? await self.value
  }
}
