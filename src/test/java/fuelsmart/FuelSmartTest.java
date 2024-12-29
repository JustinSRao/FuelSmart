package fuelsmart;

import org.junit.jupiter.api.Test;

public class FuelSmartTest {

    @Test
    public void test1(){
        String name1 = "Toyota";
        String model1 = "Corolla";
        int year1 = 2023;
        GasCar car1 = new GasCar(name1, model1, year1);

        System.out.println("ChatGPT Response 1: " + car1.carData);

        String name2 = "Tesla";
        String model2 = "X";
        int year2 = 2021;
        ElectricCar car2 = new ElectricCar(name2, model2, year2);

        System.out.println("ChatGPT Response 2: " + car2.carData);
    }

    @Test
    public void test2(){
        String name1 = "Honda";
        String model1 = "Civic";
        int year1 = 2020;
        GasCar car1 = new GasCar(name1, model1, year1);

        System.out.println("ChatGPT Response 1: " + car1.carData);

        String name2 = "Tesla";
        String model2 = "X";
        int year2 = 2022;
        ElectricCar car2 = new ElectricCar(name2, model2, year2);

        System.out.println("ChatGPT Response 2: " + car2.carData);
    }

    @Test
    public void test3(){
        String name1 = "Honda";
        String model1 = "Civic";
        int year1 = 2020;
        GasCar car1 = new GasCar(name1, model1, year1);

        System.out.println("ChatGPT Response 1: " + car1.priceInCAD);
        System.out.println("ChatGPT Response 1: " + car1.fuelTankInGallons);
        System.out.println("ChatGPT Response 1: " + car1.milesPerGallon);


        String name2 = "Tesla";
        String model2 = "X";
        int year2 = 2022;
        ElectricCar car2 = new ElectricCar(name2, model2, year2);

        System.out.println("ChatGPT Response 2: " + car2.priceInCAD);
        System.out.println("ChatGPT Response 2: " + car2.maxMilesPerCharge);
        System.out.println("ChatGPT Response 2: " + car2.batteryCapacityInKWH);


    }
}
