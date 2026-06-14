importScripts("https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDUdc3Sf1ySJFtHARU431JQvrt6Moe8T_E",
  authDomain: "philgeps-notif-alert.firebaseapp.com",
  projectId: "philgeps-notif-alert",
  storageBucket: "philgeps-notif-alert.firebasestorage.app",
  messagingSenderId: "124523489115",
  appId: "1:124523489115:web:93f7188df123b281545c7e",
  measurementId: "G-RMEJ8R1SWN"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log("Background Message:", payload);

  const title =
    payload.data?.title ||
    payload.notification?.title ||
    "PhilGEPS Notif & Alert";

  const body =
    payload.data?.body ||
    payload.notification?.body ||
    "New PhilGEPS notification.";

  const url =
    payload.data?.url ||
    "https://notices.philgeps.gov.ph/";

  const postId =
    payload.data?.postId ||
    payload.data?.post_id ||
    Date.now().toString();

  const notificationType =
    payload.data?.notificationType ||
    payload.data?.notification_type ||
    "new";

  self.registration.showNotification(title, {
    body: body,
    icon: "icons/Icon-192.png",
    badge: "icons/Icon-192.png",

    tag: `${postId}-${notificationType}`,
    renotify: false,
    requireInteraction: true,
    silent: false,

    actions: [
      {
        action: "open",
        title: "Open"
      },
      {
        action: "close",
        title: "Close"
      }
    ],

    data: {
      url: url,
      postId: postId,
      notificationType: notificationType
    }
  });
});

self.addEventListener("notificationclick", function (event) {
  event.notification.close();

  const data = event.notification.data || {};

  const url =
    data.url ||
    data?.FCM_MSG?.data?.url ||
    "https://notices.philgeps.gov.ph/";

  if (event.action === "close") {
    return;
  }

  event.waitUntil(
    clients.matchAll({
      type: "window",
      includeUncontrolled: true
    }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) {
          client.focus();
          return clients.openWindow(url);
        }
      }

      return clients.openWindow(url);
    })
  );
});

self.addEventListener("notificationclose", function (event) {
  event.notification.close();
});