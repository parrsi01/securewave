"""
Login Issue Diagnostic Tool
Tests registration and login flow to identify issues
"""

import requests
import json

BASE_URL = "https://securewave-app.azurewebsites.net"

def test_login_flow():
    print("=" * 70)
    print("LOGIN ISSUE DIAGNOSTIC TEST")
    print("=" * 70)
    print()

    # Test credentials
    test_email = "diagtest@example.com"
    test_password = "DiagTest123!@#"

    print(f"Testing with: {test_email} / {test_password}")
    print()

    # Step 1: Register
    print("STEP 1: Registering new account...")
    print("-" * 70)

    register_response = requests.post(
        f"{BASE_URL}/api/auth/register",
        json={"email": test_email, "password": test_password},
        timeout=10
    )

    print(f"Status Code: {register_response.status_code}")
    print(f"Response: {json.dumps(register_response.json(), indent=2)}")

    if register_response.status_code == 200:
        print("✓ Registration successful")
        register_data = register_response.json()
        print(f"✓ Access token received: {register_data.get('access_token')[:50]}...")
    elif register_response.status_code == 400:
        print("⚠ Email already registered (expected if re-running test)")
        register_data = None
    else:
        print(f"✗ Registration failed: {register_response.text}")
        return

    print()

    # Step 2: Login
    print("STEP 2: Attempting login with same credentials...")
    print("-" * 70)

    login_response = requests.post(
        f"{BASE_URL}/api/auth/login",
        json={"email": test_email, "password": test_password},
        timeout=10
    )

    print(f"Status Code: {login_response.status_code}")
    print(f"Response: {json.dumps(login_response.json(), indent=2)}")

    if login_response.status_code == 200:
        print("✓ Login successful")
        login_data = login_response.json()
        print(f"✓ Access token received: {login_data.get('access_token')[:50]}...")
    else:
        print(f"✗ LOGIN FAILED!")
        print(f"Error details: {login_response.json()}")
        return

    print()

    # Step 3: Test wrong password
    print("STEP 3: Testing with wrong password...")
    print("-" * 70)

    wrong_login = requests.post(
        f"{BASE_URL}/api/auth/login",
        json={"email": test_email, "password": "WrongPassword123"},
        timeout=10
    )

    print(f"Status Code: {wrong_login.status_code}")
    print(f"Response: {json.dumps(wrong_login.json(), indent=2)}")

    if wrong_login.status_code == 401:
        print("✓ Correctly rejected invalid password")
    else:
        print("✗ Security issue: Should reject wrong password!")

    print()

    # Step 4: Verify token works
    print("STEP 4: Verifying access token works...")
    print("-" * 70)

    if login_response.status_code == 200:
        token = login_response.json()['access_token']

        user_info = requests.get(
            f"{BASE_URL}/api/auth/users/me",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10
        )

        print(f"Status Code: {user_info.status_code}")
        print(f"User Info: {json.dumps(user_info.json(), indent=2)}")

        if user_info.status_code == 200:
            print("✓ Token is valid and user info retrieved")
        else:
            print("✗ Token validation failed")

    print()
    print("=" * 70)
    print("DIAGNOSTIC COMPLETE")
    print("=" * 70)
    print()

    # Summary
    if register_response.status_code in [200, 400] and login_response.status_code == 200:
        print("✓ RESULT: Login system is working correctly!")
        print()
        print("If you're experiencing issues in the browser:")
        print("1. Clear browser cache and cookies")
        print("2. Clear localStorage (F12 > Application > Local Storage > Clear)")
        print("3. Try in incognito/private mode")
        print("4. Check browser console for JavaScript errors (F12)")
    else:
        print("✗ RESULT: Login system has issues!")
        print()
        print("Issues detected:")
        if register_response.status_code not in [200, 400]:
            print(f"  - Registration failing with status {register_response.status_code}")
        if login_response.status_code != 200:
            print(f"  - Login failing with status {login_response.status_code}")

if __name__ == "__main__":
    test_login_flow()
