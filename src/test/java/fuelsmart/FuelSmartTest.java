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

        String name2 = "Toyota";
        String model2 = "Corolla";
        int year2 = 2023;
        ElectricCar car2 = new ElectricCar(name2, model2, year2);

        System.out.println("ChatGPT Response 2: " + car2.carData);
    }
}
