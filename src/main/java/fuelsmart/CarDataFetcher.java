package fuelsmart;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class CarDataFetcher {

    // ChatGPT API code for the gas car
    public static String chatGPT1(String make, String carModel, String year) {
        String apiUrl = "https://api.openai.com/v1/chat/completions";
        String apiKey = "REDACTED-REVOKED-OPENAI-KEY"; // API key goes here
        String model = "gpt-3.5-turbo";

        String message = "I want you to return to me the price in USD, the fuel tank size in gallons, and the miles per gallon value for a " + make + carModel + year + ", but return the information as text, with only 3 numbers separated by a spacebar space. I only want the numbers returned, no letters or symbols.";

        try {
            // Setup HTTP Connection
            URL url = new URL(apiUrl);
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Authorization", "Bearer " + apiKey);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setDoOutput(true);
            connection.setConnectTimeout(5000);  // 5 seconds timeout
            connection.setReadTimeout(5000);     // 5 seconds read timeout

            // Build JSON Request Body
            String requestBody = String.format(
                    "{\"model\": \"%s\", \"messages\": [{\"role\": \"user\", \"content\": \"%s\"}]}",
                    model,
                    message
            );

            // Write Request Body
            try (OutputStream os = connection.getOutputStream()) {
                byte[] input = requestBody.getBytes(StandardCharsets.UTF_8);
                os.write(input, 0, input.length);
            }

            // Read Response
            int responseCode = connection.getResponseCode();
            if (responseCode == 200) { // HTTP OK
                String response = new String(connection.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
                return extractContentFromResponse(response);
            } else {
                String errorResponse = new String(connection.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);
                System.err.println("Error Response: " + errorResponse);
                throw new RuntimeException("Failed to get response. HTTP Code: " + responseCode + ", Error: " + errorResponse);
            }

        } catch (IOException e) {
            throw new RuntimeException("Error connecting to the ChatGPT API", e);
        }
    }

    // ChatGPT API code for the electric car
    public static String chatGPT2(String make, String carModel, String year) {
        String apiUrl = "https://api.openai.com/v1/chat/completions";
        String apiKey = "REDACTED-REVOKED-OPENAI-KEY"; // API key goes here
        String model = "gpt-3.5-turbo";

        String message = "I want you to return to me the price in USD, the maximum miles per charge, and the battery capacity in KWH for a " + make + carModel + year + ", but return the information as text, with only 3 numbers separated by a spacebar space. I only want the numbers returned, no letters or symbols.";

        try {
            // Setup HTTP Connection
            URL url = new URL(apiUrl);
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Authorization", "Bearer " + apiKey);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setDoOutput(true);
            connection.setConnectTimeout(5000);  // 5 seconds timeout
            connection.setReadTimeout(5000);     // 5 seconds read timeout

            // Build JSON Request Body
            String requestBody = String.format(
                    "{\"model\": \"%s\", \"messages\": [{\"role\": \"user\", \"content\": \"%s\"}]}",
                    model,
                    message
            );

            // Write Request Body
            try (OutputStream os = connection.getOutputStream()) {
                byte[] input = requestBody.getBytes(StandardCharsets.UTF_8);
                os.write(input, 0, input.length);
            }

            // Read Response
            int responseCode = connection.getResponseCode();
            if (responseCode == 200) { // HTTP OK
                String response = new String(connection.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
                return extractContentFromResponse(response);
            } else {
                String errorResponse = new String(connection.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);
                System.err.println("Error Response: " + errorResponse);
                throw new RuntimeException("Failed to get response. HTTP Code: " + responseCode + ", Error: " + errorResponse);
            }

        } catch (IOException e) {
            throw new RuntimeException("Error connecting to the ChatGPT API", e);
        }
    }

    public static String extractContentFromResponse(String response) {
        // Parse JSON Response
        JsonObject jsonResponse = JsonParser.parseString(response).getAsJsonObject();
        JsonArray choices = jsonResponse.getAsJsonArray("choices");
        if (choices != null && choices.size() > 0) {
            JsonObject firstChoice = choices.get(0).getAsJsonObject();
            return firstChoice.getAsJsonObject("message").get("content").getAsString().trim();
        }
        return "No response content found.";
    }
}
