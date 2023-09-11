//
//  main.swift
//  photogra-method-cli
//
//  Created by 福野　泰介 on 2023/05/02.
//

import Foundation
import RealityKit

func runCommand(path: String, arguments: [String]) -> String? {
    let task = Process()
    task.launchPath = path
    task.arguments = arguments
    //task.launchPath = "/bin/bash"
    // task.arguments = ["-c", path] + arguments
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)
    
    return output
}

func convertVideoToJPEG(videoPath: String, outputFolder: String, fps: String) {
    let command = "/opt/homebrew/bin/ffmpeg"
    //let command = "ffmpeg"
    let arguments = [
        "-i",
        videoPath,
        "-qmin",
        "1",
        "-q",
        "1",
        "-r",
        fps,
        "\(outputFolder)/%04d.jpg"
    ]
    
    let res = runCommand(path: command, arguments: arguments)
    print(res ?? "no res")
}

func makeObjectCaptureFromFolder(url: URL, detail: String, sensitivity: String, order: String) {
    /*
     https://developer.apple.com/documentation/realitykit/photogrammetrysession/request/detail
    Triangles  Estimated File Size
    .preview <25k <5MB     1024 x 1024     10.666667 MB
    .reduced <50k <10MB     2048 x 2048     42.666667 MB
    .medium <100k <30MB     4096 x 4096     170.666667 MB
    .full <250k <100MB     8192 x 8192     853.33333 MB
    .raw <30M  Varies     8192 x 8192 (multiple)     Varies
     //let detail = PhotogrammetrySession.Request.Detail.preview // 2.4MB(onojo)
     //let detail = PhotogrammetrySession.Request.Detail.reduced // 13.5MB(onojo)
     //let detail = PhotogrammetrySession.Request.Detail.medium // 42MB(onojo)
     */
    //let sdetail = "reduced"
    func getDetail() -> PhotogrammetrySession.Request.Detail {
        switch (detail) {
            case "preview":
                return PhotogrammetrySession.Request.Detail.preview
            case "reduced":
                return PhotogrammetrySession.Request.Detail.reduced
            case "medium":
                return PhotogrammetrySession.Request.Detail.medium
            case "full":
                return PhotogrammetrySession.Request.Detail.full
            case "raw":
                return PhotogrammetrySession.Request.Detail.raw
            default:
                print("unsupported detail")
                Foundation.exit(1)
        }
    }
    func getSensitivity() -> PhotogrammetrySession.Configuration.FeatureSensitivity {
        switch (sensitivity) {
            case "high":
                return PhotogrammetrySession.Configuration.FeatureSensitivity.high // The session uses a slower, more sensitive algorithm to detect landmarks.
            default:
            return PhotogrammetrySession.Configuration.FeatureSensitivity.normal // The session uses the default algorithm to detect landmarks.
        }
    }
    func getOrder() -> PhotogrammetrySession.Configuration.SampleOrdering {
        switch (order) {
            case "sequential":
                return PhotogrammetrySession.Configuration.SampleOrdering.sequential
            default:
                return PhotogrammetrySession.Configuration.SampleOrdering.unordered
        }
    }

    let detail = getDetail()
    let sensitivity = getSensitivity()
    let order = getOrder();

    //let inputFolder = url.absoluteString // arguments[1]
    let inputFolder = String(url.deletingLastPathComponent().absoluteString.dropFirst(7)) + url.lastPathComponent + "/"
    let outputFilename = String(url.deletingLastPathComponent().absoluteString.dropFirst(7)) + url.lastPathComponent + ".usdz"
    //let outputFilename = url.lastPathComponent + ".usdz" // for default directory
    //let inputFolder = "/Users/fukuno/data/photo/house/img1/"
    //let outputFilename = "/Users/fukuno/data/photo/house/img1-test.usdz"

    let inputFolderUrl = URL(fileURLWithPath: inputFolder, isDirectory: true)
    let outputUrl = URL(fileURLWithPath: outputFilename, isDirectory: false)
    print(FileManager.default.currentDirectoryPath)
    var configure = PhotogrammetrySession.Configuration()
    configure.sampleOrdering = order
    configure.featureSensitivity = sensitivity
    
    do {
        let session = try PhotogrammetrySession(
            input: inputFolderUrl,
            configuration: configure
        )

        let waiter = Task {
            for try await output in session.outputs {
                switch output {
                    case .processingComplete:
                        Foundation.exit(0)
                    case .inputComplete:
                        print("Output: inputComplete")
                    case .requestError(let r, let s):
                        print("Output: requestError \(r) \(s)")
                        //view.message = "変換中にエラーが発生しました \(r) \(s)"
                    
                    case .requestComplete(_, _):
                        print("Output: requestComplete")
                        //view.message = "変換完了！"
                        //NSWorkspace.shared.open(outputUrl)

                    case .requestProgress(_, fractionComplete: let fractionComplete):
                        let progress = String(format: "%.2f", fractionComplete * 100)
                        print("Output: requestProgress \(progress)%")
                        //view.message = "進捗率 \(progress)%"
                    case .processingCancelled:
                        print("Output: processingCancelled")
                    case .invalidSample(id: _, reason: _):
                        print("Output: invalidSample")
                    case .skippedSample(id: _):
                        print("Output: automatskippedSample")
                    case .automaticDownsampling:
                        print("Output: automaticDownsampling")
                    @unknown default:
                        print("Output: unhandled message")
                }
            }
        }

        func makeRequest() -> PhotogrammetrySession.Request {
            return PhotogrammetrySession.Request.modelFile(url: outputUrl, detail: detail)
        }

        withExtendedLifetime((session, waiter)) {
            do {
                let request = makeRequest()
                print("Using request: \(String(describing: request))")
                try session.process(requests: [ request ])
                RunLoop.main.run()
            } catch {
                print("Process got error: \(String(describing: error))")
                Foundation.exit(1)
            }
        }
    } catch let e {
        print(e)
    }
}


func makeObjectCapture(url: URL, detail: String, sensitivity: String, order: String, fps: String) {
    let imageExtensions = ["mov", "mp4", "avi"]
    if imageExtensions.contains(url.pathExtension.lowercased()) {
        let videoPath = String(url.deletingLastPathComponent().absoluteString.dropFirst(7)) + url.lastPathComponent
        //print(videoPath)
        let outputFolder = String(videoPath.dropLast(url.pathExtension.count + 1))
        
        // mkdir
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: outputFolder)
        } catch _ {
            //print(e)
        }
        do {
            try fileManager.createDirectory(atPath: outputFolder, withIntermediateDirectories: true, attributes: nil)
        } catch let e {
            print(e)
        }
        //view.file = videoPath
        //view.message = "動画を静止画に変換中..."
        print("Convert request: movie to images")
        convertVideoToJPEG(videoPath: videoPath, outputFolder: outputFolder, fps: fps)
        let url2 = URL(fileURLWithPath: outputFolder)
        //print(url2)
        makeObjectCaptureFromFolder(url: url2, detail: detail, sensitivity: sensitivity, order: order)
    } else {
        makeObjectCaptureFromFolder(url: url, detail: detail, sensitivity: sensitivity, order: order)
    }
}

if (CommandLine.arguments.count == 1) {
    //print("[path] (detail preview/reduced/medium/full/raw) (sensitivity high/normal) (order sequential/orderless) (fps)")
    print("[dir path] (detail preview/reduced/medium/full/raw) (sensitivity high/normal) (order sequential/unordered)")
    Foundation.exit(1)
}
let path = CommandLine.arguments[1]
let detail = CommandLine.arguments.count <= 2 ? "reduced" : CommandLine.arguments[2]
let sensitivity = CommandLine.arguments.count <= 3 ? "high" : CommandLine.arguments[3]
let order = CommandLine.arguments.count <= 4 ? "unordered" : CommandLine.arguments[4]
//let fps = CommandLine.arguments.count <= 5 ? "2" : CommandLine.arguments[5]

let url = URL(fileURLWithPath: path)

//makeObjectCapture(url: url, detail: detail, sensitivity: sensitivity, order: order, fps: fps)
makeObjectCaptureFromFolder(url: url, detail: detail, sensitivity: sensitivity, order: order)
