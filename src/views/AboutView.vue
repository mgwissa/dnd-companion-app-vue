<template>
  <div class="about">
    <div class="character-image">
      <img src="/src/assets/korhal.png" alt="" />
    </div>
    <div>
      <h1>Korhal Dawnrender</h1>
      <ul>
        <li>
          <a
            href="https://docs.google.com/document/d/1-QXsRbLyMnCakCzoLytfaoHDeFv6txIVFQWa2-_VDbo/edit?tab=t.0#heading=h.y8m79efzv8tm"
            target="_blank"
            >Backstory</a
          >
        </li>
      </ul>
    </div>
  </div>
</template>

<style>
@media (min-width: 1024px) {
  .about {
    display: flex;
    align-items: center;
    gap: 2rem;
    min-height: 100vh;
  }

  .character-image {
    width: 40%;
    img {
      width: 100%;
      height: auto;
    }
  }
}
</style>
