import Foundation

internal protocol Cancellable {
  func cancel()
}

internal protocol Endable {
  func awaitToBeCompleted() async
}

internal typealias OperationTask = any (Cancellable & Endable)
public typealias AsyncThrowingOperation<Success> = @isolated(any) @Sendable () async throws -> sending Success
public typealias AsyncOperation<Success> = @isolated(any) @Sendable () async -> sending Success

final public class TaskQueue: @unchecked Sendable {
  
  public struct Attributes: OptionSet, Sendable {
    public let rawValue: UInt64
    
    public static let concurrent = Attributes(rawValue: 1 << 0)
    
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
  
  init(qos: TaskPriority? = nil, attributes: Attributes = []) {
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
  }
}

extension TaskQueue {
  
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
  func addBarrierOperation<Success>(
    qos: TaskPriority? = nil,
    @_inheritActorContext _ operation: @escaping AsyncThrowingOperation<Success>
  ) -> Task<Success, Error> {
    return appendAsyncThrowingOperation(
      operation,
      qos: qos,
      isBarrier: true
    )
  }
  
  func addBarrierOperation<Success>(
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
