<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('depots', function (Blueprint $table) {
            $table->increments('depot_id');
            $table->unsignedInteger('area_id');
            $table->string('csc_name', 100);
            $table->string('csc_code', 20)->nullable();
            $table->string('page_no', 10)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->timestamps();

            $table->foreign('area_id')->references('area_id')->on('areas')->onDelete('cascade');
            $table->unique(['area_id', 'csc_name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('depots');
    }
};
