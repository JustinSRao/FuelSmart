package fuelsmart;

import java.util.Scanner;

public class FuelSmart {

    public static void main(String[] args) {

        Scanner scanner = new Scanner(System.in);

        System.out.print("Enter the gas car brand/make: ");
        String makeGas = scanner.nextLine();
        System.out.println("You entered: " + makeGas);

        System.out.print("Enter the gas car model: ");
        String modelGas = scanner.nextLine();
        System.out.println("You entered: " + modelGas);

        System.out.print("Enter the gas car year: ");
        int yearGas = scanner.nextInt();
        System.out.println("You entered: " + yearGas);
        scanner.nextLine();

        System.out.println("\n");

        System.out.print("Enter the electric car brand/make: ");
        String makeElectric = scanner.nextLine();
        System.out.println("You entered: " + makeElectric);

        System.out.print("Enter the electric car model: ");
        String modelElectric = scanner.nextLine();
        System.out.println("You entered: " + modelElectric);

        System.out.print("Enter the electric car year: ");
        int yearElectric = scanner.nextInt();
        System.out.println("You entered: " + yearElectric);

        System.out.print("Enter your local price of gas in CAD/L: ");
        double priceOfGas = scanner.nextDouble();
        System.out.println("You entered: " + priceOfGas);

        System.out.print("Enter your local price of electricity in CAD/kWh: ");
        double priceOfElectricity = scanner.nextDouble();
        System.out.println("You entered: " + priceOfElectricity);

        System.out.print("How many km do you drive per year on average: ");
        double kmPerYear = scanner.nextDouble();

        scanner.close();

        System.out.println("\n");

        GasCar gasCar = new GasCar(makeGas, modelGas, yearGas);
        ElectricCar electricCar = new ElectricCar(makeElectric, modelElectric, yearElectric);

        // Gas Car Calculations
        double costOfTank = gasCar.fuelTankInLitres * priceOfGas;
        double maxMiles = gasCar.milesPerGallon * gasCar.fuelTankInGallons;
        double gasCar_pricePerMile = costOfTank / maxMiles;

        // Electric Car Calculations
        double costOfCharge = electricCar.batteryCapacityInKWH * priceOfElectricity;
        double electricCar_pricePerMile = costOfCharge / electricCar.maxMilesPerCharge;

        // Which car should the user buy?
        if (electricCar.priceInCAD < gasCar.priceInCAD) {
            System.out.println("For a cheaper (short and long term), and more fuel-efficient vehicle, you should buy the " + makeElectric + " " + modelElectric + " " + yearElectric + ".");
        }
        else if (electricCar.priceInCAD == gasCar.priceInCAD) {
            System.out.println("For a cheaper (long term), and more fuel-efficient vehicle, you should buy the " + makeElectric + " " + modelElectric + " " + yearElectric + ".");
        }
        else if (electricCar.priceInCAD > gasCar.priceInCAD) {
            double distance = (electricCar.priceInCAD - gasCar.priceInCAD) / (gasCar_pricePerMile - electricCar_pricePerMile);
            double distanceInKM = distance * 1.60934;
            double distanceRoundedInKM = Math.round(distanceInKM);
            System.out.println("You must drive a distance of " + distanceRoundedInKM + " km, so that the price evens out, and the more expensive electric car is worth buying.");

            double years = distanceInKM / kmPerYear;
            double yearsRounded = Math.round(years);

            System.out.println("You would have to drive the " + makeGas + " " + modelGas + " " + yearGas + " approximately " + yearsRounded + " years until the cost reaches that of the " + makeElectric + " " + modelElectric + " " + yearElectric + ".");
        }
    }
}
