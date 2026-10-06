(function () {
  'use strict';

  var form = document.getElementById('contact-form');
  var msgEl = document.getElementById('form-message');

  if (!form || !msgEl) return;

  function getCookie(name) {
    var match = document.cookie.match(new RegExp('(?:^|;\\s*)' + name + '=([^;]*)'));
    return match ? decodeURIComponent(match[1]) : null;
  }

  function showMessage(text, isError) {
    msgEl.textContent = text;
    msgEl.className = 'form-message visible' + (isError ? ' error' : '');
  }

  function clearMessage() {
    msgEl.textContent = '';
    msgEl.className = 'form-message';
  }

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    clearMessage();

    var nameVal = form.elements.name.value.trim();
    var emailVal = form.elements.email.value.trim();
    var subjectVal = form.elements.subject.value;
    var messageVal = form.elements.message.value.trim();

    if (!nameVal || !emailVal || !subjectVal || !messageVal) {
      showMessage('Please fill in all required fields.', true);
      return;
    }

    var emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailPattern.test(emailVal)) {
      showMessage('Please enter a valid email address.', true);
      return;
    }

    var submitBtn = form.querySelector('button[type="submit"]');
    submitBtn.disabled = true;
    submitBtn.textContent = 'Sending...';

    var headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };

    var csrfToken = getCookie('csrftoken') || getCookie('csrf_token');
    if (csrfToken) {
      headers['X-CSRF-Token'] = csrfToken;
    }

    fetch('/api/contact/submit', {
      method: 'POST',
      headers: headers,
      credentials: 'same-origin',
      body: JSON.stringify({
        name: nameVal,
        email: emailVal,
        subject: subjectVal,
        message: messageVal
      })
    })
    .then(function (response) {
      if (!response.ok) {
        return response.json().then(function (data) {
          throw new Error(data.detail || data.message || 'Something went wrong. Please try again.');
        });
      }
      return response.json();
    })
    .then(function () {
      showMessage('Thank you for your message. We will get back to you within 24 hours.', false);
      form.reset();
    })
    .catch(function (err) {
      showMessage(err.message || 'Unable to send your message. Please try again later.', true);
    })
    .finally(function () {
      submitBtn.disabled = false;
      submitBtn.textContent = 'Send Message';
    });
  });
})();
