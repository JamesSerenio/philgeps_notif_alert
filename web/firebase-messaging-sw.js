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
});

self.addEventListener("notificationclick", function (event) {
  event.notification.close();

  const url =
    event.notification.data?.FCM_MSG?.data?.url ||
    event.notification.data?.url ||
    "https://notices.philgeps.gov.ph/";

  event.waitUntil(
    clients.openWindow(url)
  );
});