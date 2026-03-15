class HelpContent {
  static const String termsOfService = """
1. Acceptance of Terms
By using AirLink, you agree to these terms. If you do not agree, please do not use the application.

2. Description of Service
AirLink is a decentralized, mesh-networking based messaging application that allows communication without the need for active internet or cellular infrastructure.

3. Privacy & Data
AirLink is designed with privacy in mind. Since it operates as a mesh network, your messages are relayed through peers. All messages are end-to-end encrypted. We do not collect or store your personal data on any central server.

4. User Responsibilities
You are responsible for your own device and the content you share. You agree not to use AirLink for any illegal or harmful activities.

5. Disclaimer of Warranties
AirLink is provided "as is" without any warranties. We do not guarantee continuous, uninterrupted, or secure access to the service.

6. Limitation of Liability
We shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of the application.
""";

  static const String privacyPolicy = """
1. Data Collection
AirLink does not collect personal information like phone numbers or email addresses. Your identity is tied to your device ID and a display name of your choice.

2. Message Encryption
All messages sent via AirLink are end-to-end encrypted. Only the intended recipient can decrypt and read your messages.

3. Local Storage
Your chat history and profile information are stored locally on your device. Clearing your app data will permanently delete this information.

4. Peer-to-Peer Networking
Messages are transmitted directly between devices or relayed through other AirLink users in the mesh. While relaying, nodes cannot read the content of the messages due to encryption.

5. Location Data
AirLink may use Bluetooth and Wi-Fi Direct for discovery. Approximate location permissions are required by the Android system for these technologies to function, but we do not track or store your location history.
""";

  static const String appInfo = """
AirLink is a cutting-edge communication tool designed for resilience and privacy. 

Version: 2.0.0
Build: Premium Stable
Developer: AirID Mesh Labs
Engine: Flutter 3.x
Network Protocol: AirID Mesh v1.2

AirLink was built to provide a reliable means of communication in areas with poor connectivity, during natural disasters, or for users who prioritize sovereign, private communication.
""";

  static const String workingMesh = """
How AirLink Works

1. No Internet Required
AirLink uses the Wi-Fi and Bluetooth hardware in your phone to create a local "mesh" network. It doesn't need cell towers or internet routers.

2. Peer-to-Peer Discovery
When you open AirLink, it starts "Advertising" its presence and "Browsing" for others. Once two devices are in range, they automatically establish a secure link.

3. Message Relaying (The Mesh)
If you want to send a message to a person who is too far away, but there's another AirLink user between you both, your message will "hop" through that middle device to reach its destination.

4. Secure & Private
Every message is locked with end-to-end encryption. Even if a message hops through 10 different devices, none of them can see what's inside.

5. Range
Typical range is 30-100 meters depending on the environment. By having more users in an area, the network's total reach expands significantly.
""";
}
