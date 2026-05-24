/*
  Arcade Bridge - Arduino Pro Micro (ATmega32U4)
  
  Converts arcade GPIO button inputs to USB HID keyboard output.
  Mirrors the Raspberry Pi GPIO pin mapping for easy migration.
  
  Hardware: Arduino Pro Micro (5V, 16MHz)
  Wiring: Connect arcade button ground to Arduino ground
          Connect arcade button signal to specified Arduino pins
          Arcade buttons are ACTIVE LOW (pull-up resistor in Arduino)
  
  Target: MacBook running ElectroBun arcade app
  Output: USB HID Keyboard events
*/

#include <Keyboard.h>

// Pin count - Arduino Pro Micro has 18 digital I/O pins (0-17)
// Using pins 0-17 for arcade controls (18 buttons max per Arduino)
// For full 30 buttons (4 players + system), use 2 Arduinos or analog pins

// Player 1 (Pins 0-6) - Arrow keys + Z/X/Enter
#define P1_LEFT     0   // Left Arrow
#define P1_UP       1   // Up Arrow
#define P1_RIGHT    2   // Right Arrow
#define P1_DOWN     3   // Down Arrow
#define P1_A        4   // Z key
#define P1_B        5   // X key
#define P1_MENU     6   // Enter key

// Player 2 (Pins 7-13) - WASD + Q/W/E
#define P2_LEFT     7   // A key
#define P2_UP       8   // W key
#define P2_RIGHT    9   // D key
#define P2_DOWN     10  // S key
#define P2_A        11  // Q key
#define P2_B        12  // E key (or keep available for P3/P4)
#define P2_MENU     13  // Tab key

// Second Arduino or extended pins for Players 3-4
// Uncomment if using single Arduino with analog pins as digital
// #define P3_LEFT   A0
// #define P3_UP     A1
// etc...

// Debounce delay in milliseconds
#define DEBOUNCE_MS 20

// Button state tracking
struct Button {
  uint8_t pin;
  char key;
  bool lastState;
  unsigned long lastDebounceTime;
};

// Button definitions - Player 1
Button buttons[] = {
  {P1_LEFT, KEY_LEFT_ARROW, false, 0},
  {P1_UP, KEY_UP_ARROW, false, 0},
  {P1_RIGHT, KEY_RIGHT_ARROW, false, 0},
  {P1_DOWN, KEY_DOWN_ARROW, false, 0},
  {P1_A, 'z', false, 0},
  {P1_B, 'x', false, 0},
  {P1_MENU, KEY_RETURN, false, 0},
  
  {P2_LEFT, 'a', false, 0},
  {P2_UP, 'w', false, 0},
  {P2_RIGHT, 'd', false, 0},
  {P2_DOWN, 's', false, 0},
  {P2_A, 'q', false, 0},
  {P2_B, 'e', false, 0},
  {P2_MENU, KEY_TAB, false, 0},
};

const int NUM_BUTTONS = sizeof(buttons) / sizeof(buttons[0]);

void setup() {
  // Initialize serial for debugging (optional)
  Serial.begin(9600);
  delay(1000);
  Serial.println("Arcade Bridge starting...");
  
  // Initialize all button pins as INPUT_PULLUP
  // Buttons connect to GND when pressed (active LOW)
  for (int i = 0; i < NUM_BUTTONS; i++) {
    pinMode(buttons[i].pin, INPUT_PULLUP);
    buttons[i].lastState = digitalRead(buttons[i].pin);
  }
  
  // Initialize USB keyboard
  Keyboard.begin();
  
  Serial.println("Arcade Bridge ready!");
  Serial.print("Buttons configured: ");
  Serial.println(NUM_BUTTONS);
}

void loop() {
  unsigned long currentTime = millis();
  
  for (int i = 0; i < NUM_BUTTONS; i++) {
    // Read current pin state (inverted because pull-up: LOW = pressed)
    bool pinState = digitalRead(buttons[i].pin);
    bool isPressed = !pinState;  // Button pressed when LOW
    
    // Check if state changed
    if (pinState != buttons[i].lastState) {
      buttons[i].lastDebounceTime = currentTime;
    }
    
    // Debounce check
    if ((currentTime - buttons[i].lastDebounceTime) > DEBOUNCE_MS) {
      // State is stable, check for press/release
      if (isPressed && !buttons[i].lastState) {
        // Button pressed
        Keyboard.press(buttons[i].key);
        Serial.print("Pressed: ");
        Serial.println(buttons[i].key);
      } else if (!isPressed && buttons[i].lastState) {
        // Button released
        Keyboard.release(buttons[i].key);
        Serial.print("Released: ");
        Serial.println(buttons[i].key);
      }
      
      buttons[i].lastState = isPressed;
    }
    
    // Update last raw state for debouncing
    buttons[i].lastState = pinState;
  }
  
  // Small delay to prevent USB flooding
  delay(1);
}

/*
  EXTENDED VERSION - Two Arduinos for 4 Players
  
  Arduino #1 (Players 1-2):
  - Same as above
  
  Arduino #2 (Players 3-4 + System):
  
  Player 3 - UHJK + I/O/P
  #define P3_LEFT     0   // U
  #define P3_UP       1   // H
  #define P3_RIGHT    2   // K
  #define P3_DOWN     3   // J
  #define P3_A        4   // I
  #define P3_B        5   // O
  #define P3_MENU     6   // P
  
  Player 4 - Numpad or extended keys
  #define P4_LEFT     7   // 4
  #define P4_UP       8   // 8
  #define P4_RIGHT    9   // 6
  #define P4_DOWN     10  // 2
  #define P4_A        11  // 1
  #define P4_B        12  // 3
  #define P4_MENU     13  // Enter
  
  System Buttons
  #define BTN_RESET   A0  // R
  #define BTN_EXIT    A1  // Escape
  
  Or use analog pins A0-A3 for 4 extra buttons on second Arduino.
*/
