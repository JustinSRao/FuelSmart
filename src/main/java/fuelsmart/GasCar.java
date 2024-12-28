package fuelsmart;

public class GasCar {

    double priceInCAD;
    double fuelTankInGallons;
    double fuelTankInLitres;
    double milesPerGallon;
    String carData;

    // Constructor
    public GasCar(String make, String model, int year) {
        String y = String.valueOf(year);
        double exchangeRate = 1.44;

        try {
            // Fetch car data
            String carData = CarDataFetcher.chatGPT1(make, model, y);

            // Split the string by spaces
            String[] parts = carData.split(" ");

            if (parts.length != 3) {
                throw new IllegalArgumentException("Invalid API response: Expected 3 numbers but got " + parts.length);
            }

            // Convert the parts to doubles
            double[] numbers = new double[parts.length];
            for (int i = 0; i < parts.length; i++) {
                numbers[i] = Double.parseDouble(parts[i]);
            }

            // Assign values from API response
            this.priceInCAD = numbers[0] * exchangeRate;
            this.fuelTankInGallons = numbers[1];
            this.fuelTankInLitres = fuelTankInGallons * 3.78541; // Convert gallons to litres
            this.milesPerGallon = numbers[2];
            this.carData = carData;

        } catch (Exception e) {
            throw new RuntimeException("Failed to initialize GasCar: " + e.getMessage(), e);
        }
    }


    @Override
    public String toString() {
        return String.format("Gas Car:\nPrice in CAD: %.2f\nFuel Tank Capacity: %.2f gallons (%.2f litres)\nMiles per Gallon: %.2f",
                priceInCAD, fuelTankInGallons, fuelTankInLitres, milesPerGallon);
    }
}
