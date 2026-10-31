import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

enum FriendRequestState { friends, sent, incoming, none }

class FriendService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _friendRef(
    String uid,
    String other,
  ) => _db.collection('users').doc(uid).collection('friends').doc(other);

  DocumentReference<Map<String, dynamic>> _requestRef(
    String receiver,
    String sender,
  ) => _db
      .collection('users')
      .doc(receiver)
      .collection('friendRequests')
      .doc(sender);

  Future<FriendRequestState> state(String me, String other) async {
    if (me == other) return FriendRequestState.none;
    if ((await _friendRef(me, other).get()).exists)
      return FriendRequestState.friends;
    if ((await _requestRef(other, me).get()).exists)
      return FriendRequestState.sent;
    if ((await _requestRef(me, other).get()).exists)
      return FriendRequestState.incoming;
    return FriendRequestState.none;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> incoming(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('friendRequests')
      .orderBy('createdAt', descending: true)
      .snapshots();

  Future<void> send({required String from, required String to}) async {
    if (from.isEmpty || to.isEmpty || from == to) return;
    final status = await state(from, to);
    if (status == FriendRequestState.friends ||
        status == FriendRequestState.sent)
      return;
    if (status == FriendRequestState.incoming) {
      await accept(receiver: from, sender: to);
      return;
    }
    await _requestRef(
      to,
      from,
    ).set({'senderId': from, 'createdAt': FieldValue.serverTimestamp()});
    try {
      await NotificationService().create(
        toUid: to,
        fromUid: from,
        type: 'friend_request',
      );
    } catch (_) {}
  }

  Future<void> cancel({required String sender, required String receiver}) =>
      _requestRef(receiver, sender).delete();

  Future<void> accept({
    required String receiver,
    required String sender,
  }) async {
    if (receiver == sender) return;
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(_friendRef(receiver, sender), {'createdAt': now});
    batch.set(_friendRef(sender, receiver), {'createdAt': now});
    batch.delete(_requestRef(receiver, sender));
    await batch.commit();
    try {
      await NotificationService().create(
        toUid: sender,
        fromUid: receiver,
        type: 'friend_accepted',
      );
    } catch (_) {}
  }

  Future<void> decline({required String receiver, required String sender}) =>
      _requestRef(receiver, sender).delete();

  Future<void> unfriend({required String me, required String other}) async {
    final batch = _db.batch();
    batch.delete(_friendRef(me, other));
    batch.delete(_friendRef(other, me));
    await batch.commit();
  }
}
