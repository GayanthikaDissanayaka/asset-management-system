<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->increments('user_id');
            $table->string('name', 100);
            $table->string('email', 150)->unique();
            $table->string('password_hash', 255);
            $table->enum('role', ['admin', 'area_engineer', 'depot_engineer', 'field_technician', 'viewer']);
            $table->unsignedInteger('depot_id')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('depot_id')->references('depot_id')->on('depots')->onDelete('set null');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('users');
    }
};
