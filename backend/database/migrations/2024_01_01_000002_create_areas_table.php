<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('areas', function (Blueprint $table) {
            $table->increments('area_id');
            $table->unsignedInteger('province_id');
            $table->unsignedTinyInteger('area_no');
            $table->string('area_name', 100);
            $table->timestamps();

            $table->foreign('province_id')->references('province_id')->on('provinces')->onDelete('cascade');
            $table->unique(['province_id', 'area_name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('areas');
    }
};
