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

  const data = payload.data || {};
  const title = data.title || "PhilGEPS Notif & Alert";
  const body = data.body || "New PhilGEPS update detected.";

  self.registration.showNotification(title, {
    body,
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
    tag: `${data.postId || Date.now()}-${data.notificationType || "alert"}`,
    requireInteraction: true,
    data: data,
    actions: [
      {
        action: "add_bidding_open",
        title: "👍 Bidding Docs",
      },
    ],
  });
});

self.addEventListener("notificationclick", function (event) {
  event.notification.close();

  const rawData = event.notification.data || {};
  const fcmData = rawData.FCM_MSG?.data || {};
  const data = Object.keys(fcmData).length ? fcmData : rawData;

  const postId =
    data.postId ||
    data.post_id ||
    "";

  let url =
    data.url ||
    "https://notices.philgeps.gov.ph/";

  const refMatch = url.match(/refID=(\d+)/i);
  const refId = refMatch ? refMatch[1] : postId;

  if (refId) {
    url =
      `https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/SplashBidNoticeAbstractUI.aspx?menuIndex=3&refID=${refId}&highlight=true`;
  }

  const apiUrl =
    data.apiUrl ||
    "https://philgepsnotifalert-production.up.railway.app/add-bidding-doc";

  if (event.action === "add_bidding_open") {
    event.waitUntil(
      fetch(apiUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          postId: postId || refId
        })
      }).finally(() => {
        return clients.openWindow(url);
      })
    );
    return;
  }

  event.waitUntil(
    clients.openWindow(url)
  );
});

self.addEventListener("notificationclose", function (event) {
  event.notification.close();
});