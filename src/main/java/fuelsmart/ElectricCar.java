package fuelsmart;

public class ElectricCar {

    double priceInCAD;
    double maxMilesPerCharge;
    double batteryCapacityInKWH;
    String carData;

    // Constructor
    public ElectricCar(String make, String model, int year) {
        String y = String.valueOf(year);
        double exchangeRate = 1.44;

        try {
            // Fetch car data
            String carData = CarDataFetcher.chatGPT2(make, model, y);

            // Validate and split the response
            if (carData == null || !carData.matches("\\d+(\\.\\d+)? \\d+(\\.\\d+)? \\d+(\\.\\d+)?")) {
                throw new IllegalArgumentException("Invalid API response format for ElectricCar: " + carData);
            }

            // Split the string by spaces
            String[] parts = carData.split(" ");
            if (parts.length != 3) {
                throw new IllegalArgumentException("API response for ElectricCar did not contain exactly 3 values: " + carData);
            }

            // Convert the parts to doubles
            double[] numbers = new double[parts.length];
            for (int i = 0; i < parts.length; i++) {
                numbers[i] = Double.parseDouble(parts[i]);
            }

            // Assign values from API response
            this.priceInCAD = numbers[0] * exchangeRate;
            this.maxMilesPerCharge = numbers[1];
            this.batteryCapacityInKWH = numbers[2];
            this.carData = carData;

        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Failed to parse car data: " + e.getMessage(), e);
        } catch (RuntimeException e) {
            throw new RuntimeException("Failed to fetch or initialize ElectricCar: " + e.getMessage(), e);
        }
    }


    @Override
    public String toString() {
        return String.format("Electric Car:\nPrice in CAD: %.2f\nMax Miles Per Charge: %.2f\nBattery Capacity: %.2f kWh",
                priceInCAD, maxMilesPerCharge, batteryCapacityInKWH);
    }
}
