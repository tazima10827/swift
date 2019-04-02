//
//  DataConnectionViewController.swift
//  swift
//
//

import UIKit
import SkyWay

class DataConnectionViewController: UIViewController {

    fileprivate var peer: SKWPeer?
    fileprivate var dataConnection: SKWDataConnection?
    fileprivate var mediaConnection: SKWMediaConnection?
    fileprivate var localStream: SKWMediaStream?
    fileprivate var remoteStream: SKWMediaStream?
    
    
    var messages = [Message]()
    struct Message{
        enum SenderType:String{
            case send
            case get
        }
        var sender:SenderType = .send
        var text:String?
    }
    
    @IBOutlet weak var myPeerIdLabel: UILabel!
    @IBOutlet weak var targetPeerIdLabel: UILabel!
    @IBOutlet weak var messageTableView: UITableView!
    @IBOutlet weak var messageTextField: UITextField!
    @IBOutlet weak var callButton: UIButton!
    @IBOutlet weak var endCallButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // TableView Design
        messageTableView.estimatedRowHeight = 20
        messageTableView.rowHeight = UITableViewAutomaticDimension
        messageTableView.tableFooterView = UIView()
        
        // Setup SkySway
        self.setup()
//        self.callsetup()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.dataConnection?.close()
        self.mediaConnection?.close()
        self.peer?.disconnect()
        self.peer?.destroy()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func tapCall(){
        guard let peer = self.peer else{
            return
        }

        Util.callPeerIDSelectDialog(peer: peer, myPeerId: peer.identity) { (peerId) in
            self.connect(targetPeerId: peerId)
        }
        
    }
    
    @IBAction func tapEndCall(){
        self.dataConnection?.close()
        self.mediaConnection?.close()
        self.changeConnectionStatusUI(connected: false)
    }
    
    @IBAction func tapSend(){
        guard let text = self.messageTextField.text else{
            return
        }
        
        self.view.endEditing(true)
        self.dataConnection?.send(text as NSObject)
        let message = Message(sender: DataConnectionViewController.Message.SenderType.send, text: text)
        self.messages.insert(message, at: 0)
        self.messageTableView.reloadData()
        self.messageTextField.text = nil
        
        guard let peer = self.peer else{
            return
        }
        Util.callPeerIDSelectDialog(peer: peer, myPeerId: peer.identity) { (peerId) in
            self.call(targetPeerId: peerId)
        }
    }
    
    func changeConnectionStatusUI(connected:Bool){
        if connected {
            self.callButton.isEnabled = false
            self.endCallButton.isEnabled = true
            self.sendButton.isEnabled = true
        }else{
            self.callButton.isEnabled = true
            self.endCallButton.isEnabled = false
            self.sendButton.isEnabled = false
        }
    }
}

// MARK: setup skyway

extension DataConnectionViewController{
    
    func setup(){
        
        guard let apikey = (UIApplication.shared.delegate as? AppDelegate)?.skywayAPIKey, let domain = (UIApplication.shared.delegate as? AppDelegate)?.skywayDomain else{
            print("Not set apikey or domain")
            return
        }
        
        let option: SKWPeerOption = SKWPeerOption.init();
        option.key = apikey
        option.domain = domain
        
        peer = SKWPeer(options: option)
        
        if let _peer = peer{
            self.setupPeerCallBacks(peer: _peer)
            self.setupStream(peer: _peer)
        }else{
            print("failed to create peer setup")
        }
        
    }
    
    func connect(targetPeerId:String){
        let options = SKWConnectOption()
        options.serialization = SKWSerializationEnum.SERIALIZATION_BINARY
        
        //接続
        if let dataConnection = peer?.connect(withId: targetPeerId, options: options){
            self.dataConnection = dataConnection
            self.setupDataConnectionCallbacks(dataConnection: dataConnection)
        }else{
            print("failed to connect data connection")
        }
    }
}

// MARK: skyway callbacks

extension DataConnectionViewController{
    
    func setupPeerCallBacks(peer:SKWPeer){
        
        // MARK: PEER_EVENT_ERROR
        peer.on(SKWPeerEventEnum.PEER_EVENT_ERROR, callback:{ (obj) -> Void in
            if let error = obj as? SKWPeerError{
                print("\(error)")
            }
        })
        
        // MARK: PEER_EVENT_OPEN
        peer.on(SKWPeerEventEnum.PEER_EVENT_OPEN,callback:{ (obj) -> Void in
            if let peerId = obj as? String{
                DispatchQueue.main.async {
                    self.myPeerIdLabel.text = peerId
                    self.myPeerIdLabel.textColor = UIColor.darkGray
                }
                print("your peerId: \(peerId)")
            }
        })
        
        // MARK: PEER_EVENT_CONNECTION
        peer.on(SKWPeerEventEnum.PEER_EVENT_CONNECTION, callback: { (obj) -> Void in
            if let connection = obj as? SKWDataConnection{
                self.dataConnection = connection
                self.setupDataConnectionCallbacks(dataConnection: connection)
            }
        })
        
        // MARK: PEER_EVENT_CONNECTION
        peer.on(SKWPeerEventEnum.PEER_EVENT_CALL, callback: { (obj) -> Void in
            if let connection = obj as? SKWMediaConnection{
                self.setupMediaConnectionCallbacks(mediaConnection: connection)
                self.mediaConnection = connection
                connection.answer(self.localStream)
            }
        })
    }
    
    func setupDataConnectionCallbacks(dataConnection:SKWDataConnection){
        
        // MARK: DATACONNECTION_EVENT_OPEN
        dataConnection.on(SKWDataConnectionEventEnum.DATACONNECTION_EVENT_OPEN, callback: { (obj) -> Void in
            if let dataConnection = obj as? SKWDataConnection{
                self.targetPeerIdLabel.text = dataConnection.peer
                self.targetPeerIdLabel.textColor = UIColor.darkGray
            }
            self.changeConnectionStatusUI(connected: true)
        })
        
        // MARK: DATACONNECTION_EVENT_DATA
        dataConnection.on(SKWDataConnectionEventEnum.DATACONNECTION_EVENT_DATA, callback: { (obj) -> Void in
            let strValue:String = obj as! String
            print("get data: \(strValue)")
            let message = Message(sender: DataConnectionViewController.Message.SenderType.get, text: strValue)
            self.messages.insert(message, at: 0)
            self.messageTableView.reloadData()
        })
        
        // MARK: DATACONNECTION_EVENT_CLOSE
        dataConnection.on(SKWDataConnectionEventEnum.DATACONNECTION_EVENT_CLOSE, callback: { (obj) -> Void in
            print("close data connection")
            self.dataConnection = nil
            self.changeConnectionStatusUI(connected: false)
        })
    }
}

// MARK: UITableViewDelegate UITableViewDataSource

extension DataConnectionViewController: UITableViewDelegate, UITableViewDataSource{
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MessageTableViewCell
        cell.messageLabel?.text = messages[indexPath.row].text
        cell.senderLabel?.text = messages[indexPath.row].sender.rawValue

        return cell
    }
}

// MARK: UITextFieldDelegate

extension DataConnectionViewController: UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return true
    }
}

// MARK: TableView Cell

class MessageTableViewCell:UITableViewCell{
    @IBOutlet weak var messageLabel:UILabel!
    @IBOutlet weak var senderLabel:UILabel!
}


extension DataConnectionViewController{
    func setupStream(peer:SKWPeer){
        SKWNavigator.initialize(peer);
        let constraints:SKWMediaConstraints = SKWMediaConstraints()
        self.localStream = SKWNavigator.getUserMedia(constraints)
//        self.localStream?.addVideoRenderer(self.localStreamView, track: 0)
    }
    
    func call(targetPeerId:String){
        let option = SKWCallOption()
        
        if let mediaConnection = self.peer?.call(withId: targetPeerId, stream: self.localStream, options: option){
            self.mediaConnection = mediaConnection
            self.setupMediaConnectionCallbacks(mediaConnection: mediaConnection)
        }else{
            print("failed to call :\(targetPeerId)")
        }
    }
}

// MARK: skyway callbacks

extension DataConnectionViewController{
    
    func setupMediaConnectionCallbacks(mediaConnection:SKWMediaConnection){
        
        // MARK: MEDIACONNECTION_EVENT_STREAM
        mediaConnection.on(SKWMediaConnectionEventEnum.MEDIACONNECTION_EVENT_STREAM, callback: { (obj) -> Void in
            if let msStream = obj as? SKWMediaStream{
                self.remoteStream = msStream
                DispatchQueue.main.async {
                    self.targetPeerIdLabel.text = self.remoteStream?.peerId
                    self.targetPeerIdLabel.textColor = UIColor.darkGray
                    //                    self.remoteStream?.addVideoRenderer(self.remoteStreamView, track: 0)
                }
                self.changeConnectionStatusUI(connected: true)
            }
        })
        
        // MARK: MEDIACONNECTION_EVENT_CLOSE
        mediaConnection.on(SKWMediaConnectionEventEnum.MEDIACONNECTION_EVENT_CLOSE, callback: { (obj) -> Void in
            if let _ = obj as? SKWMediaConnection{
                DispatchQueue.main.async {
//                    self.remoteStream?.removeVideoRenderer(self.remoteStream, track: 0)
                    self.remoteStream = nil
                    self.mediaConnection = nil
                }
                self.changeConnectionStatusUI(connected: false)
            }
        })
    }
}

