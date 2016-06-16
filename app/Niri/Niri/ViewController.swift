//
//  ViewController.swift
//  Niri
//
//  Created by Thukral, Vishal on 6/11/16.
//  Copyright © 2016 Thukral, Vishal. All rights reserved.
//

import UIKit
import AVFoundation
import SpeechToTextV1
import CoreLocation

class ViewController: UIViewController, AVAudioRecorderDelegate, AVAudioPlayerDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var transcriptionDisplay: UITextView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    
    @IBOutlet weak var startStopStreamingDefaultButton: UIButton!
    @IBOutlet weak var transcribeButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    
    var recorder: AVAudioRecorder!
    var locationManager: CLLocationManager!
    var stt: SpeechToText?
    var player: AVAudioPlayer?
    var isStreamingDefault = false
    var stopStreamingDefault: (Void -> Void)? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // create file to store recordings
        let documents = NSSearchPathForDirectoriesInDomains(.DocumentDirectory,
                                                            .UserDomainMask, true)[0]
        let filename = "SpeechToTextRecording.wav"
        let filepath = NSURL(fileURLWithPath: documents + "/" + filename)

        // set up session and recorder
        let session = AVAudioSession.sharedInstance()
        var settings = [String: AnyObject]()
        settings[AVSampleRateKey] = NSNumber(float: 44100.0)
        settings[AVNumberOfChannelsKey] = NSNumber(int: 1)
        do {
            try session.setCategory(AVAudioSessionCategoryPlayAndRecord)
            recorder = try AVAudioRecorder(URL: filepath, settings: settings)
        } catch {
            failure("Audio Recording", message: "Error setting up session/recorder.")
        }
        
        // ensure recorder is set up
        guard let recorder = recorder else {
            failure("AVAudioRecorder", message: "Could not set up recorder.")
            return
        }
        
        // prepare recorder to record
        recorder.delegate = self
        recorder.meteringEnabled = true
        recorder.prepareToRecord()
        startStandardUpdates()
        instantiateSTT()
        

    }
    
    func instantiateSTT() {
        
        // identify credentials file
        let bundle = NSBundle(forClass: self.dynamicType)
        guard let credentialsURL = bundle.pathForResource("Credentials", ofType: "plist") else {
            failure("Loading Credentials", message: "Unable to locate credentials file.")
            return
        }
        
        // load credentials file
        let dict = NSDictionary(contentsOfFile: credentialsURL)
        guard let credentials = dict as? Dictionary<String, String> else {
            failure("Loading Credentials", message: "Unable to read credentials file.")
            return
        }
        
        // read SpeechToText username
        guard let user = credentials["SpeechToTextUsername"] else {
            failure("Loading Credentials", message: "Unable to read Speech to Text username.")
            return
        }
        
        // read SpeechToText password
        guard let password = credentials["SpeechToTextPassword"] else {
            failure("Loading Credentials", message: "Unable to read Speech to Text password.")
            return
        }
        
        stt = SpeechToText(username: user, password: password)
    }
    
    override func viewWillAppear(animated: Bool) {
        stopButton.enabled = false
        playButton.enabled = false
        transcribeButton.enabled = false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func failure(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        let ok = UIAlertAction(title: "OK", style: .Default) { action in }
        alert.addAction(ok)
        presentViewController(alert, animated: true) { }
    }
  
    @IBAction func recordPauseTapped(sender: AnyObject) {
        // ensure recorder is set up
        guard let recorder = recorder else {
            failure("Start/Pause Recording", message: "Recorder not properly set up.")
            return
        }

        
        if let player = player {
            if player.playing {
                player.stop()
            }
        }
        
        //start pause recording
        if !recorder.recording {
            let session = AVAudioSession.sharedInstance()
            
            do{
                try session.setActive(true)
                recorder.record()
                recordButton.setTitle("Pause", forState: UIControlState.Normal)
            }
            catch{
                 failure("Start/Pause Recording", message: "Error setting session active.")
            }
            
        }
        else{
            recorder.pause()
            recordButton.setTitle("Record", forState: UIControlState.Normal)
        }
        
        stopButton.enabled = true
        playButton.enabled = false
        transcribeButton.enabled = false
    }
    
    @IBAction func stopTapped(sender: AnyObject) {
        guard let recorder = recorder else {
            failure("StopTapped", message: "Recorder not properly set up.")
            return
        }
        recorder.stop()
        let session = AVAudioSession.sharedInstance()
        do{
            try session.setActive(false)
            transcribeButton.enabled = true
            playButton.enabled = true
            stopButton.enabled = false
            recordButton.setTitle("Record", forState: UIControlState.Normal)
        }
        catch{
            failure("Start/Stop Recording", message: "Error setting session inactive.")
        }
        
    }
    
    @IBAction func playTapped(sender: AnyObject) {
        guard let recorder = recorder else {
            failure("PlayTapped", message: "Recorder not properly set up.")
            return
        }
    
        if !recorder.recording{
            do {
                player = try AVAudioPlayer(contentsOfURL: recorder.url)
                player?.play()
            } catch {
                failure("Play Recording", message: "Error creating audio player.")
            }
        }
    }
    
    
    @IBAction func transcribeTapped(sender: AnyObject) {
        // ensure recorder is set up
        guard let recorder = recorder else {
            failure("Transcribe", message: "Recorder not properly set up.")
            return
        }
        
        // ensure SpeechToText service is set up
        guard let stt = stt else {
            failure("Transcribe", message: "SpeechToText not properly set up.")
            return
        }
        
        // load data from saved recording
        guard let data = NSData(contentsOfURL: recorder.url) else {
            failure("Transcribe", message: "Error retrieving saved recording data.")
            return
        }
        
        // transcribe recording
        var settings = TranscriptionSettings(contentType: .WAV)
        //settings.model = "en-UK_BroadbandModel"
        stt.transcribe(data, settings: settings, failure: failureData) { results in
            print("\(results)")
            self.showResults(results)
        }
    }
    
    func failureData(error: NSError) {
        let title = "Speech to Text Error:\nTranscribe"
        let message = error.localizedDescription
        failure(title, message: message)
    }

    
    func showResults(results: [TranscriptionResult]) {
            var text = ""
            
            for result in results {
                if let transcript = result.alternatives.last?.transcript where result.final == true {
                    let title = titleCase(transcript)
                    text += String(title.characters.dropLast()) + "." + " "
                }
            }
            
            if results.last?.final == false {
                if let transcript = results.last?.alternatives.last?.transcript {
                    text += titleCase(transcript)
                }
            }
            
            self.transcriptionDisplay.text = text
    }
    
    func titleCase(s: String) -> String {
        let first = String(s.characters.prefix(1)).uppercaseString
        return first + String(s.characters.dropFirst())
    }

    
    func audioPlayerDidFinishPlaying(player: AVAudioPlayer, successfully flag: Bool) {
        
    }
    
    @IBAction func startStreaming(sender: AnyObject) {
        
        // stop if already streaming
        if (isStreamingDefault) {
            stopStreamingDefault?()
            startStopStreamingDefaultButton.setTitle("Start Streaming (Default)", forState: .Normal)
            isStreamingDefault = false
            return
        }
        
        // set streaming
        isStreamingDefault = true
        
        // change button title
        startStopStreamingDefaultButton.setTitle("Stop Streaming (Default)", forState: .Normal)
        
        // ensure SpeechToText service is up
        guard let stt = stt else {
            failure("STT Streaming (Default)", message: "SpeechToText not properly set up.")
            return
        }
        
        // configure settings for streaming
        var settings = TranscriptionSettings(contentType: .L16(rate: 44100, channels: 1))
        
        settings.continuous = true
        settings.interimResults = true
        //settings.model = "en-UK_BroadbandModel"
        
        // start streaming from microphone
        stopStreamingDefault = stt.transcribe(settings, failure: failureDefault) { results in
            self.showResults(results)
        }

    }
    
    func failureDefault(error: NSError) {
        let title = "Speech to Text Error:\nStreaming (Default)"
        let message = error.localizedDescription
        let alert = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        let ok = UIAlertAction(title: "OK", style: .Default) { action in
            self.stopStreamingDefault?()
            self.startStopStreamingDefaultButton.enabled = true
            self.startStopStreamingDefaultButton.setTitle("Start Streaming (Default)",
                                                          forState: .Normal)
            self.isStreamingDefault = false
        }
        alert.addAction(ok)
        presentViewController(alert, animated: true) { }
    }
    
    func audioRecorderDidFinishRecording(recorder: AVAudioRecorder, successfully flag: Bool) {
        
    }
    
    /*
     * Location
     *
     *
     */
    
    func startStandardUpdates() {
        if locationManager == nil{
           locationManager = CLLocationManager()
        }
        
        locationManager.delegate = self;
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        
        //locationManager.distanceFilter = 500
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
    }
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations[locations.endIndex-1]
        let eventDate = location.timestamp
        let howRecent = eventDate.timeIntervalSinceNow
        print("bar")
        if abs(howRecent) < 15.0{
            print("latitude: \(location.coordinate.latitude)\n longitude: \(location.coordinate.longitude)")
        }
        
    }
    

}

