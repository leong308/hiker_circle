'use strict';

// Updated devices filter data-only chat pushes locally; older builds retain visible system alerts.
function chatPush({token, recipientPhone, localFilter, chatId, messageId, title, body, deepLink}) {
  const base = {token, data: {type: 'group_chat_message', chatId, messageId, title, body, deepLink, recipientPhone}, android: {priority: 'high'}};
  return localFilter ? {...base,
    apns: {headers: {'apns-priority': '5', 'apns-push-type': 'background'}, payload: {aps: {contentAvailable: true}}}}
    : {...base, notification: {title, body}, android: {priority: 'high', notification: {priority: 'high'}},
      apns: {headers: {'apns-priority': '10'}, payload: {aps: {sound: 'default'}}}};
}
module.exports = {chatPush};
