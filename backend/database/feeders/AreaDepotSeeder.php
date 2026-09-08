<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Province;
use App\Models\Area;
use App\Models\Depot;

class AreaDepotSeeder extends Seeder
{
    public function run(): void
    {
        $province = Province::firstOrCreate(['province_name' => 'Uva']);

        $structure = [
            1 => ['name' => 'Mahiyanganaya', 'depots' => [
                ['Mahiyanganaya', '01'], ['Rideemaliyadda', '02'], ['Kandaketiya', '03'],
            ]],
            2 => ['name' => 'Badulla', 'depots' => [
                ['Badulla', '04'], ['Haliela', '05'], ['Passara', '06'],
            ]],
            3 => ['name' => 'Diyathalawa', 'depots' => [
                ['Diyathalawa', '07'], ['Bandarawela', '08'], ['Welimada', '09'],
                ['Uva-paranagama', '10'], ['Ella', '11'],
            ]],
            4 => ['name' => 'Monaragala', 'depots' => [
                ['Monaragala', '12'], ['Dambagalla', '13'], ['Bibila', '14'],
            ]],
            5 => ['name' => 'Wellawaya', 'depots' => [
                ['Wellawaya', '15'], ['Buttala', '16'], ['Thanamalwila', '17'],
            ]],
        ];

        foreach ($structure as $areaNo => $data) {
            $area = Area::firstOrCreate(
                ['province_id' => $province->province_id, 'area_name' => $data['name']],
                ['area_no' => $areaNo]
            );

            foreach ($data['depots'] as [$cscName, $pageNo]) {
                Depot::firstOrCreate(
                    ['area_id' => $area->area_id, 'csc_name' => $cscName],
                    ['page_no' => $pageNo]
                );
            }
        }
    }
}
