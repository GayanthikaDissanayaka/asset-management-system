<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\AssetCategory;
use App\Models\AssetType;

class AssetTypeSeeder extends Seeder
{
    public function run(): void
    {
        $categories = [
            'Transformer' => [
                ['Distribution Transformer', 'nos', false],
            ],
            'Substation' => [
                ['Distribution Substation', 'nos', false],
                ['Grid Substation', 'nos', false],
            ],
            'Switchgear' => [
                ['LBS (Load Break Switch)', 'nos', false],
                ['RMU (Ring Main Unit)', 'nos', false],
                ['Isolator', 'nos', false],
            ],
            'Cable' => [
                ['Underground Cable', 'km', true],
            ],
            'Conductor' => [
                ['Copper Conductor', 'km', true],
                ['Weasel Conductor', 'km', true],
                ['Raccoon Conductor', 'km', true],
                ['Lynx Conductor', 'km', true],
                ['Fly Conductor', 'km', true],
                ['Zebra Conductor', 'km', true],
                ['ABC (Aerial Bundled Cable)', 'km', true],
            ],
            'Pole' => [
                ['Concrete Pole', 'nos', false],
                ['Wooden Pole', 'nos', false],
            ],
            'Power Line' => [
                ['LV Line', 'km', true],
                ['MV Line', 'km', true],
                ['HV Line', 'km', true],
            ],
        ];

        foreach ($categories as $categoryName => $types) {
            $category = AssetCategory::firstOrCreate(['category_name' => $categoryName]);

            foreach ($types as [$typeName, $unit, $isLine]) {
                AssetType::firstOrCreate(
                    ['category_id' => $category->category_id, 'type_name' => $typeName],
                    ['unit_of_measure' => $unit, 'is_line_asset' => $isLine]
                );
            }
        }
    }
}
