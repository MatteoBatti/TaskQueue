# TaskQueue

A thread-safe, Swift-native task queue that provides ordered execution of asynchronous operations with support for both serial and concurrent execution modes.

## Features

- ✅ **Thread-safe operations** with built-in synchronization
- ✅ **Serial and concurrent execution modes**
- ✅ **Barrier operations** for synchronization points
- ✅ **Quality of Service (QoS) support** for priority-based execution
- ✅ **Actor context inheritance** using `@_inheritActorContext`
- ✅ **Automatic memory management** with cleanup of cancelled operations
- ✅ **Swift Concurrency native** - built with async/await and Task APIs
- ✅ **iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+** support

## Installation

### Swift Package Manager

Add TaskQueue to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/TaskQueue.git", from: "1.0.0")
]
```

## Quick Start

### Basic Serial Queue

```swift
import TaskQueue

// Create a serial queue (default behavior)
let queue = TaskQueue()

// Add operations that execute in order
let task1 = queue.addOperation {
    print("First operation")
    return "result1"
}

let task2 = queue.addOperation {
    print("Second operation") // Runs after first completes
    return "result2"
}

// Get results
let result1 = await task1.value // "result1"
let result2 = await task2.value // "result2"
```

### Concurrent Queue

```swift
// Create a concurrent queue
let concurrentQueue = TaskQueue(attributes: [.concurrent])

// Add operations that can run in parallel
concurrentQueue.addOperation {
    await downloadFile1()
}

concurrentQueue.addOperation {
    await downloadFile2() // Can run simultaneously with downloadFile1()
}

concurrentQueue.addOperation {
    await downloadFile3()
}
```

## Advanced Usage

### Barrier Operations

Barrier operations provide synchronization points in concurrent queues:

```swift
let concurrentQueue = TaskQueue(attributes: [.concurrent])

// Phase 1: Parallel downloads
concurrentQueue.addOperation { await downloadFile("file1.txt") }
concurrentQueue.addOperation { await downloadFile("file2.txt") }
concurrentQueue.addOperation { await downloadFile("file3.txt") }

// Synchronization point: wait for all downloads to complete
concurrentQueue.addBarrierOperation {
    print("All downloads completed!")
    await consolidateDownloadedFiles()
}

// Phase 2: These operations wait for the barrier to complete
concurrentQueue.addOperation { await processConsolidatedData() }
concurrentQueue.addOperation { await uploadResults() }
```

### Quality of Service (QoS)

Control execution priority with QoS levels:

```swift
// High-priority queue for UI-critical operations
let uiQueue = TaskQueue(qos: .userInitiated, attributes: [.concurrent])

// Background queue for non-critical work
let backgroundQueue = TaskQueue(qos: .utility)

// Override QoS for specific operations
backgroundQueue.addOperation(qos: .userInitiated) {
    // This operation runs with higher priority
    return await urgentBackgroundTask()
}
```

### Error Handling

TaskQueue supports both throwing and non-throwing operations:

```swift
let queue = TaskQueue()

// Throwing operation
let throwingTask = queue.addOperation {
    if Bool.random() {
        throw NetworkError.timeout
    }
    return "success"
}

// Handle the result
do {
    let result = try await throwingTask.value
    print("Success: \(result)")
} catch {
    print("Failed: \(error)")
}

// Non-throwing operation
let safeTask = queue.addOperation {
    return await processDataSafely() // Cannot throw
}

let result = await safeTask.value // No error handling needed
```

### Actor Context Inheritance

Operations automatically inherit the calling actor's context:

```swift
actor DataProcessor {
    private var cache: [String: Data] = [:]
    
    func processFiles() async {
        let queue = TaskQueue(attributes: [.concurrent])
        
        // These operations inherit the DataProcessor actor context
        let task1 = queue.addOperation {
            let data = await loadFile("file1.txt")
            self.cache["file1"] = data // Direct access to actor state
            return data.count
        }
        
        let task2 = queue.addOperation {
            let data = await loadFile("file2.txt") 
            self.cache["file2"] = data // Also runs on DataProcessor
            return data.count
        }
        
        let sizes = await [task1.value, task2.value]
        print("File sizes: \(sizes)")
    }
}
```

### Cancellation

Cancel operations individually or clear the entire queue:

```swift
let queue = TaskQueue()

// Add some operations
let task1 = queue.addOperation { await longRunningOperation1() }
let task2 = queue.addOperation { await longRunningOperation2() }

// Cancel individual operation
task1.cancel()

// Or cancel all operations in the queue
queue.cancelAllOperations()
```

## Real-World Examples

### Image Processing Pipeline

```swift
class ImageProcessor {
    private let processingQueue = TaskQueue(qos: .userInitiated, attributes: [.concurrent])
    private let saveQueue = TaskQueue(qos: .utility) // Serial for file operations
    
    func processImages(_ urls: [URL]) async throws -> [ProcessedImage] {
        // Phase 1: Download images concurrently
        var downloadTasks: [Task<UIImage, Error>] = []
        
        for url in urls {
            let task = processingQueue.addOperation {
                return try await self.downloadImage(from: url)
            }
            downloadTasks.append(task)
        }
        
        // Phase 2: Process downloaded images
        var processingTasks: [Task<ProcessedImage, Error>] = []
        
        for downloadTask in downloadTasks {
            let task = processingQueue.addOperation {
                let image = try await downloadTask.value
                return try await self.applyFilters(to: image)
            }
            processingTasks.append(task)
        }
        
        // Phase 3: Save processed images serially
        var results: [ProcessedImage] = []
        
        for processingTask in processingTasks {
            let saveTask = saveQueue.addOperation {
                let processedImage = try await processingTask.value
                try await self.saveImage(processedImage)
                return processedImage
            }
            results.append(try await saveTask.value)
        }
        
        return results
    }
}
```

### API Request Batching

```swift
class APIClient {
    private let requestQueue = TaskQueue(qos: .userInitiated, attributes: [.concurrent])
    private let rateLimitQueue = TaskQueue() // Serial to respect rate limits
    
    func batchFetchUserData(userIDs: [String]) async throws -> [UserData] {
        let batchSize = 10
        var results: [UserData] = []
        
        // Process users in batches to respect API rate limits
        for batch in userIDs.chunked(into: batchSize) {
            let batchTask = rateLimitQueue.addBarrierOperation {
                // Within each batch, make concurrent requests
                var batchTasks: [Task<UserData, Error>] = []
                
                for userID in batch {
                    let task = self.requestQueue.addOperation {
                        return try await self.fetchUser(id: userID)
                    }
                    batchTasks.append(task)
                }
                
                // Collect batch results
                var batchResults: [UserData] = []
                for task in batchTasks {
                    batchResults.append(try await task.value)
                }
                
                return batchResults
            }
            
            results.append(contentsOf: try await batchTask.value)
        }
        
        return results
    }
}
```

## API Reference

### TaskQueue

#### Initializers
- `init(qos: TaskPriority? = nil, attributes: Attributes = [])` - Creates a new TaskQueue

#### Methods
- `addOperation(qos: TaskPriority? = nil, operation: @escaping AsyncThrowingOperation<Success>) -> Task<Success, Error>`
- `addOperation(qos: TaskPriority? = nil, operation: @escaping AsyncOperation<Success>) -> Task<Success, Never>`
- `addBarrierOperation(qos: TaskPriority? = nil, operation: @escaping AsyncThrowingOperation<Success>) -> Task<Success, Error>`
- `addBarrierOperation(qos: TaskPriority? = nil, operation: @escaping AsyncOperation<Success>) -> Task<Success, Never>`
- `cancelAllOperations()` - Cancels all queued operations

### TaskQueue.Attributes

#### Options
- `.concurrent` - Enables concurrent execution of operations

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift 6.0+
- Xcode 16.0+

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

TaskQueue is available under the MIT license. See the LICENSE file for more info.
